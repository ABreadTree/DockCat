import AppKit
import UniformTypeIdentifiers

@MainActor
final class DockCatApplication: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let usageStatisticsStore = UsageStatisticsStore()
    private let collectableInventoryStore = CollectableInventoryStore()
    private let userDataBackupStore = UserDataBackupStore()
    private let outingCatalogLoader = OutingCatalogLoader()
    private let giftCodeRedeemer = GiftCodeRedeemer()
    private let outingWakeResolver = OutingWakeResolver()
    private let assetLoader = AssetPackLoader()
    private let stateScheduler = StateScheduler()
    private let dockObserver = DockObserver()
    private let appIconStore = AppIconStore()
    private let iconController = AppIconController()
    private let dockMenuController = DockMenuController()
    private let catMenuController = CatMenuController()
    private let walkAnimator = SpriteAnimator()

    private var settings: AppSettings = .defaults
    private var activitySpace = DockGeometry.currentActivitySpace(
        activityDisplayID: AppSettings.defaults.activityDisplayID,
        startPositionPercent: AppSettings.defaults.startPositionPercent
    )
    private var outingCatalog: OutingCatalog = .empty
    private var collectableInventory: CollectableInventory = .empty
    private var defaultAssetPack: CatAssetPack!
    private var assetPack: CatAssetPack!
    private var renderer: PoseRenderer!
    private var catWindow: CatWindowController!
    private var interactionController: CatInteractionController!
    private var stateMachine: CatStateMachine!
    private var reminderScheduler: ReminderScheduler!
    private var settingsWindowController: SettingsWindowController!
    private var usageSessionTracker: UsageSessionTracker!
    private var reminderTimer: Timer?
    private var outingTimer: Timer?
    private var startupTimer: Timer?
    private var walkMovementTimer: Timer?
    private var agentHTTPServer: AgentHTTPServer?
    private var agentEventQueue = AgentEventQueue()
    private var activeAgentPresentation: AgentPresentation?
    private var activeAgentPresentationToken = 0
    private var agentPresentationTimer: Timer?
    private var agentPatrolTimer: Timer?
    private var agentResumeTimer: Timer?
    private var stateEndDate: Date?
    private var walkDirection: CGFloat = 1
    private var pendingOutingDuration: TimeInterval?
    private var pendingOutingReturnReward: OutingReward?
    private var shouldUseStartPositionForNextTransition = false
    private var giftCodeInputWindow: NSWindow?
    private var giftCodeSuccessWindow: NSWindow?
    private var giftCodeCallbackTargets: [CallbackTarget] = []

    private var strings: AppStrings {
        AppStrings(language: settings.language)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        RuntimeDiagnostics.record("applicationDidFinishLaunching")
        settings = settingsStore.load()
        activitySpace = currentActivitySpace()
        outingCatalog = outingCatalogLoader.loadCatalog()
        collectableInventory = collectableInventoryStore.load()
        configureUsageSessionTracker()
        assetLoader.prepareCustomPacksDirectory(refreshDefaultPackBackup: true)
        defaultAssetPack = assetLoader.loadDefaultPack()
        assetPack = assetLoader.loadSelectedPack(selectedID: settings.selectedAssetPackID)
        RuntimeDiagnostics.record("loaded assetPack id=\(assetPack.id) root=\(assetPack.rootURL.path)")
        iconController.updateIconSource(appIconStore.prepareActiveIconSource(selectedPack: assetPack))
        iconController.applyPersistentFileIconIfNeeded()
        renderer = PoseRenderer(pack: assetPack, fallbackPack: defaultAssetPack)
        reminderScheduler = ReminderScheduler(settings: settings)
        catWindow = CatWindowController()
        settingsWindowController = SettingsWindowController(
            store: settingsStore,
            settings: settings,
            usageStatistics: usageSessionTracker.snapshot,
            outingCatalog: outingCatalog,
            collectableInventory: collectableInventory,
            dialogueImage: renderer.randomPose(for: .dialogue).image
        )
        configureSettingsAssetPackActions()
        catWindow.setImageScale(percent: settings.catScalePercent)
        configureStateMachine()
        configureInteraction()
        configureMenus()
        configureApplicationMenu()
        configureDockObserver()
        configureAgentHTTPServer()
        RuntimeDiagnostics.record("activitySpace frame=\(activitySpace.screenFrame) visible=\(activitySpace.visibleFrame) edge=\(activitySpace.dockEdge) entrance=\(activitySpace.entrancePoint)")
        iconController.showSleepIcon()
        catWindow.hide()
#if DEBUG
        if showDebugOutingGiftPreviewIfRequested() {
            startReminderPolling()
            return
        }
#endif
        if !restoreActiveOutingIfNeeded() {
            scheduleStartupStretch()
        }
        if !stateMachine.state.isOuting {
            startReminderPolling()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        iconController.showSleepIcon()
        clearInterruptedOutingIfNeeded()
        startupTimer?.invalidate()
        reminderTimer?.invalidate()
        outingTimer?.invalidate()
        agentHTTPServer?.stop()
        agentPresentationTimer?.invalidate()
        agentPatrolTimer?.invalidate()
        agentResumeTimer?.invalidate()
        stateScheduler.cancel()
        stopWalk()
        usageSessionTracker.stop()
        removeUsageSessionObservers()
    }

    private func clearInterruptedOutingIfNeeded() {
        guard case .outing = stateMachine.state else {
            return
        }
        settings.activeOutingEndDate = nil
        settings.activeOutingDuration = nil
        settingsStore.save(settings)
        pendingOutingDuration = nil
        pendingOutingReturnReward = nil
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        dockMenuController.applicationDockMenu(sender)
    }

#if DEBUG
    private func showDebugOutingGiftPreviewIfRequested() -> Bool {
        guard let collectableID = debugOutingGiftPreviewID() else {
            return false
        }
        guard let collectable = outingCatalog.collectables.first(where: { $0.id == collectableID }) else {
            DockCatLog.app.warning("Debug outing gift preview collectable not found: \(collectableID)")
            return false
        }
        let pose = renderer.randomPose(for: .dialogue)
        let point = startPositionAnchor()
        stateMachine.updateVisiblePosition(point)
        catWindow.setImage(pose.image, mirrored: pose.mirrored)
        catWindow.show(at: point)
        catWindow.showImageBubble(
            message: strings.outingReturnCollectable(salutation: settings.userSalutation),
            image: collectableImage(collectable),
            imageTitle: strings.collectableName(collectable),
            primaryTitle: strings.receiveGift,
            onPrimary: { [weak self] in
                self?.catWindow.hideBubble()
            }
        )
        RuntimeDiagnostics.record("debug outing gift preview collectableID=\(collectableID)")
        return true
    }

    private func debugOutingGiftPreviewID() -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        let flag = "--preview-outing-gift"
        for (index, argument) in arguments.enumerated() {
            if argument == flag, arguments.indices.contains(index + 1) {
                return arguments[index + 1]
            }
            if argument.hasPrefix("\(flag)=") {
                let value = String(argument.dropFirst(flag.count + 1))
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
#endif

    private func configureStateMachine() {
        stateMachine = CatStateMachine(
            initialPosition: startPositionAnchor(),
            entranceProvider: { [weak self] in
                guard let self else { return .zero }
                return self.startPositionAnchor()
            },
            walkingDurationRange: durationRange(
                minimum: settings.walkDurationMinimum,
                maximum: settings.walkDurationMaximum,
                fallback: AppSettings.defaults.walkDurationMinimum ... AppSettings.defaults.walkDurationMaximum
            ),
            restingDurationRange: durationRange(
                minimum: settings.restDurationMinimum,
                maximum: settings.restDurationMaximum,
                fallback: AppSettings.defaults.restDurationMinimum ... AppSettings.defaults.restDurationMaximum
            )
        )
        stateMachine.onTransition = { [weak self] _, newState in
            guard let self else { return }
            self.stateScheduler.cancel()
            self.stopWalk()
            self.stateEndDate = nil
            self.applyState(newState)
            Task { @MainActor in
                self.showNextQueuedAgentPresentationIfPossible()
            }
        }
        stateMachine.onDurationScheduled = { [weak self] state, duration in
            self?.stateEndDate = Date().addingTimeInterval(duration)
            self?.stateScheduler.schedule(after: duration) { [weak self] in
                guard let self else { return }
                self.stateMachine.finishScheduledState(state)
            }
        }
    }

    private func configureInteraction() {
        interactionController = CatInteractionController(catView: catWindow.catView)
        interactionController.onContextMenu = { [weak self] event in
            guard let self else { return }
            self.catMenuController.show(snapshot: self.statusSnapshot(), language: self.settings.language, at: event, in: self.catWindow.catView)
        }
        interactionController.onBeginDrag = { [weak self] in
            self?.stateMachine.beginDrag()
        }
        interactionController.onDrag = { [weak self] point in
            guard let self else { return }
            if case .outing(.leaving) = self.stateMachine.state {
                let outingPoint = self.outingWalkOutDragPoint(point)
                self.stateMachine.updateOutingWalkPosition(outingPoint)
                self.catWindow.setAnchor(outingPoint)
                self.catWindow.setMirrored(false)
                return
            }
            if case .outing(.returning) = self.stateMachine.state {
                return
            }
            let clamped = self.clampedCatPoint(point)
            self.stateMachine.updateVisiblePosition(clamped)
            self.catWindow.setAnchor(clamped)
        }
        interactionController.onEndDrag = { [weak self] point in
            guard let self else { return }
            if case .outing(.leaving) = self.stateMachine.state {
                let outingPoint = self.outingWalkOutDragPoint(point)
                self.stateMachine.updateOutingWalkPosition(outingPoint)
                self.catWindow.setAnchor(outingPoint)
                self.catWindow.setMirrored(false)
                return
            }
            if case .outing(.returning) = self.stateMachine.state {
                return
            }
            let clamped = self.clampedCatPoint(point)
            if case .dragged = self.stateMachine.state {
                self.stateMachine.endDrag(at: clamped)
            } else {
                self.stateMachine.updateVisiblePosition(clamped)
                self.catWindow.setAnchor(clamped)
            }
        }
    }

    private func configureMenus() {
        catMenuController.onPet = { [weak self] in self?.petCat() }
        catMenuController.onOuting = { [weak self] in self?.beginOutingPromptIfAvailable() }
        catMenuController.onSettings = { [weak self] in self?.showSettings() }
        catMenuController.onSleep = { NSApplication.shared.terminate(nil) }

        dockMenuController.stateProvider = { [weak self] in self?.stateMachine.state ?? .resting }
        dockMenuController.statusProvider = { [weak self] in self?.statusSnapshot() }
        dockMenuController.settingsProvider = { [weak self] in self?.settings ?? .defaults }
        dockMenuController.onPet = { [weak self] in self?.petCat() }
        dockMenuController.onOuting = { [weak self] in self?.beginOutingPromptIfAvailable() }
        dockMenuController.onRecall = { [weak self] in self?.showRecallConfirmation() }
        dockMenuController.onSettings = { [weak self] in self?.showSettings() }
        dockMenuController.onSleep = { NSApplication.shared.terminate(nil) }

        settingsWindowController.onSave = { [weak self] updated in
            guard let self else { return }
            let previousAssetPackID = self.settings.selectedAssetPackID
            let previousCatActivityScope = self.settings.catActivityScope
            let previousLanguage = self.settings.language
            self.settings = updated
            self.reminderScheduler.updateSettings(updated)
            if updated.language != previousLanguage {
                self.configureApplicationMenu()
            }
            if updated.selectedAssetPackID != previousAssetPackID {
                self.reloadSelectedAssetPack()
                self.applyState(self.stateMachine.state)
            }
            self.catWindow.setImageScale(percent: updated.catScalePercent)
            self.activitySpace = self.currentActivitySpace()
            let shouldResetPosition = previousCatActivityScope == .desktop && updated.catActivityScope == .dockEdge
            let point = shouldResetPosition ? self.startPositionAnchor() : self.clampedCatPoint(self.stateMachine.position)
            self.updateCurrentPositionPreservingState(point)
            self.updateStateMachineParameters()
            self.saveUserDataBackup()
        }
    }

    private func saveUserDataBackup() {
        userDataBackupStore.save(
            settings: settings,
            usageStatistics: usageSessionTracker.snapshot,
            collectableInventory: collectableInventory
        )
    }

    private func configureSettingsAssetPackActions() {
        settingsWindowController.assetPackIDsProvider = { [weak self] in
            guard let self else { return [] }
            return self.assetLoader.customPackIDs()
        }
        settingsWindowController.onOpenAssetPacksFolder = { [weak self] in
            guard let self else { return }
            self.assetLoader.prepareCustomPacksDirectory()
            NSWorkspace.shared.open(self.assetLoader.customPacksRoot())
        }
        settingsWindowController.onRestoreData = { [weak self] in
            self?.beginUserDataRestore()
        }
        settingsWindowController.onRedeemGiftCode = { [weak self] language in
            self?.beginGiftCodeRedemption(language: language)
        }
        settingsWindowController.onLoadAssetPack = { [weak self] selectedID in
            guard let self else {
                return AssetPackPreviewResult(
                    report: AssetPackValidationReport(
                        requestedID: selectedID,
                        pack: nil,
                        errorDescription: "DockCat 尚未准备好资源包加载器。",
                        poseStatuses: [],
                        walkFrameCount: 0,
                        hasValidSleepIcon: false,
                        hasValidEmptyIcon: false
                    ),
                    dialogueImage: nil
                )
            }
            let report = self.assetLoader.validationReport(for: selectedID)
            let previewImage = report.pack.map {
                PoseRenderer(pack: $0, fallbackPack: self.defaultAssetPack).randomPose(for: .dialogue).image
            } ?? self.renderer.randomPose(for: .dialogue).image
            return AssetPackPreviewResult(report: report, dialogueImage: previewImage)
        }
    }

    private func beginUserDataRestore() {
        guard confirmUserDataRestore() else { return }

        let panel = NSOpenPanel()
        panel.title = strings.restoreDataChooseFileTitle
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.directoryURL = userDataBackupStore.backupDirectoryURL

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        do {
            let result = try userDataBackupStore.restoreData(from: url, outingCatalog: outingCatalog)
            applyUserDataRestore(result)
            showUserDataRestoreSuccess(skippedCollectableNames: result.skippedCollectableNames)
        } catch {
            DockCatLog.app.error("Failed to restore user data backup: \(error.localizedDescription)")
            showAlert(title: strings.restoreDataFailureTitle, message: strings.restoreDataInvalidFileMessage)
        }
    }

    private func confirmUserDataRestore() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = strings.restoreDataConfirmTitle
        alert.informativeText = strings.restoreDataConfirmMessage
        alert.addButton(withTitle: strings.settingsRestoreData)
        alert.addButton(withTitle: strings.alertCancel)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func applyUserDataRestore(_ result: UserDataRestoreResult) {
        collectableInventory = result.collectableInventory
        collectableInventoryStore.save(result.collectableInventory)
        usageStatisticsStore.save(result.usageStatistics)
        usageSessionTracker.replaceStatistics(result.usageStatistics)
        settingsWindowController.update(usageStatistics: usageSessionTracker.snapshot)
        settingsWindowController.update(collectableInventory: collectableInventory)
        saveUserDataBackup()
    }

    private func showUserDataRestoreSuccess(skippedCollectableNames: [String]) {
        var message = strings.restoreDataSuccessMessage
        if !skippedCollectableNames.isEmpty {
            message += "\n\n\(strings.restoreDataSkippedCollectablesHeader)\n"
            message += skippedCollectableNames.map { "• \($0)" }.joined(separator: "\n")
        }
        showAlert(title: strings.restoreDataSuccessTitle, message: message)
    }

    private func beginGiftCodeRedemption(language: AppLanguage) {
        showGiftCodeInputWindow(language: language)
    }

    private func redeemGiftCode(_ code: String, language: AppLanguage) {
        let codeStrings = AppStrings(language: language)
        guard let collectableID = giftCodeRedeemer.collectableID(for: code, in: outingCatalog),
              let collectable = outingCatalog.collectables.first(where: { $0.id == collectableID })
        else {
            showAlert(title: codeStrings.giftCodeInvalidTitle, message: "", okTitle: codeStrings.assetPackAlertOK)
            return
        }

        _ = collectableInventory.recordCollectable(collectable.id)
        collectableInventoryStore.save(collectableInventory)
        settingsWindowController.update(collectableInventory: collectableInventory)
        saveUserDataBackup()
        showGiftCodeSuccess(collectable, language: language)
    }

    private func showGiftCodeInputWindow(language: AppLanguage) {
        giftCodeInputWindow?.close()
        giftCodeInputWindow = nil
        giftCodeCallbackTargets.removeAll()
        let codeStrings = AppStrings(language: language)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 292, height: 150),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = codeStrings.settingsRedeemGiftCode
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        window.collectionBehavior = [.canJoinAllSpaces]
        window.center()

        let contentView = NSView()
        window.contentView = contentView

        let titleLabel = NSTextField(labelWithString: codeStrings.giftCodeInputTitle)
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleLabel.alignment = .center

        let subtitleLabel = NSTextField(labelWithString: codeStrings.giftCodeInputSubtitle)
        subtitleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center

        let codeField = NSTextField(string: "")
        codeField.isEditable = true
        codeField.isSelectable = true
        codeField.usesSingleLineMode = true

        let cancelButton = NSButton(title: codeStrings.alertCancel, target: nil, action: nil)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let submitButton = NSButton(title: codeStrings.giftCodeSubmit, target: nil, action: nil)
        submitButton.bezelStyle = .rounded
        submitButton.keyEquivalent = "\r"

        let buttonRow = NSStackView(views: [cancelButton, submitButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 10

        for view in [titleLabel, subtitleLabel, codeField, buttonRow] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            codeField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 10),
            codeField.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            codeField.widthAnchor.constraint(equalToConstant: 176),
            buttonRow.topAnchor.constraint(equalTo: codeField.bottomAnchor, constant: 14),
            buttonRow.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            buttonRow.widthAnchor.constraint(equalToConstant: 184),
            buttonRow.heightAnchor.constraint(equalToConstant: 28)
        ])

        let cancelTarget = CallbackTarget {
            window.close()
            self.giftCodeInputWindow = nil
            self.giftCodeCallbackTargets.removeAll()
        }
        let submitTarget = CallbackTarget {
            let code = codeField.stringValue
            window.close()
            self.giftCodeInputWindow = nil
            self.giftCodeCallbackTargets.removeAll()
            self.redeemGiftCode(code, language: language)
        }
        giftCodeCallbackTargets = [cancelTarget, submitTarget]
        cancelButton.target = cancelTarget
        cancelButton.action = #selector(CallbackTarget.invoke)
        submitButton.target = submitTarget
        submitButton.action = #selector(CallbackTarget.invoke)

        giftCodeInputWindow = window
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(codeField)
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
    }

    private func showGiftCodeSuccess(_ collectable: OutingCollectable, language: AppLanguage) {
        giftCodeSuccessWindow?.close()
        let codeStrings = AppStrings(language: language)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 204),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = codeStrings.settingsRedeemGiftCode
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        window.collectionBehavior = [.canJoinAllSpaces]
        window.center()

        let contentView = NSView()
        window.contentView = contentView

        let titleLabel = NSTextField(labelWithString: codeStrings.giftCodeSuccessTitle)
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleLabel.alignment = .center

        let imageView = NSImageView()
        imageView.image = collectableImage(collectable)
        imageView.imageScaling = .scaleProportionallyUpOrDown

        let nameLabel = NSTextField(labelWithString: codeStrings.collectableName(collectable))
        nameLabel.alignment = .center
        nameLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1

        let okButton = NSButton(title: codeStrings.giftCodeDone, target: nil, action: nil)
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"

        for view in [titleLabel, imageView, nameLabel, okButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            imageView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 80),
            imageView.heightAnchor.constraint(equalToConstant: 80),
            nameLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            okButton.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 16),
            okButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            okButton.widthAnchor.constraint(equalToConstant: 96)
        ])

        let okTarget = CallbackTarget {
            window.close()
            self.giftCodeSuccessWindow = nil
            self.giftCodeCallbackTargets.removeAll()
        }
        giftCodeCallbackTargets.append(okTarget)
        okButton.target = okTarget
        okButton.action = #selector(CallbackTarget.invoke)

        giftCodeSuccessWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
    }

    private func showAlert(title: String, message: String, okTitle: String? = nil) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        if !message.isEmpty {
            alert.informativeText = message
        }
        alert.addButton(withTitle: okTitle ?? strings.assetPackAlertOK)
        alert.runModal()
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "DockCat")
        appMenu.addItem(menuItem(strings.menuPet, #selector(petFromMenu)))
        appMenu.addItem(menuItem(strings.menuGoOut, #selector(startOutingFromMenu)))
        appMenu.addItem(menuItem(strings.menuSettings, #selector(openSettingsFromMenu), keyEquivalent: ","))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(menuItem(strings.menuSleep, #selector(quitFromMenu), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    private func menuItem(_ title: String, _ action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func configureUsageSessionTracker() {
        usageSessionTracker = UsageSessionTracker(
            statistics: usageStatisticsStore.load(),
            onChange: { [weak self] statistics in
                self?.usageStatisticsStore.save(statistics)
            }
        )
        usageSessionTracker.start()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(self, selector: #selector(workspaceWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(workspaceDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(screensDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(screensDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    private func removeUsageSessionObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    @objc private func workspaceWillSleep() {
        usageSessionTracker.screenDidSleep()
    }

    @objc private func workspaceDidWake() {
        usageSessionTracker.screenDidWake()
        resolveActiveOutingAfterWake()
    }

    @objc private func screensDidSleep() {
        usageSessionTracker.screenDidSleep()
    }

    @objc private func screensDidWake() {
        usageSessionTracker.screenDidWake()
        resolveActiveOutingAfterWake()
    }

    private func showSettings() {
        RuntimeDiagnostics.record("showSettings requested")
        settingsWindowController.update(settings: settings)
        settingsWindowController.update(usageStatistics: usageSessionTracker.snapshot)
        settingsWindowController.update(collectableInventory: collectableInventory)
        settingsWindowController.update(dialogueImage: renderer.randomPose(for: .dialogue).image)
        DispatchQueue.main.async { [weak self] in
            RuntimeDiagnostics.record("showSettings presenting")
            self?.settingsWindowController.show()
        }
    }

    private func statusSnapshot() -> CatStatusSnapshot {
        CatStatusSnapshot(
            state: stateMachine.state,
            stateEndDate: stateEndDate,
            outingEndDate: settings.activeOutingEndDate
        )
    }

    private func configureDockObserver() {
        dockObserver.onChange = { [weak self] in
            guard let self else { return }
            self.activitySpace = self.currentActivitySpace()
            let clamped = self.clampedCatPoint(self.stateMachine.position)
            let walkRange = self.activitySpace.walkRangeForContent(
                width: self.catWindow.catFrameSize.width,
                scope: self.settings.catActivityScope
            )
            RuntimeDiagnostics.record(
                "workspace changed state=\(self.stateMachine.state.description) position=\(self.stateMachine.position) clamped=\(clamped) walkRange=\(walkRange) speed=\(self.settings.walkBaseSpeed)"
            )
            self.stateMachine.updateVisiblePosition(clamped)
            self.catWindow.setAnchor(clamped)
            self.catWindow.refreshVisibilityAfterWorkspaceChange()
        }
        dockObserver.start()
    }

    private func currentActivitySpace() -> ActivitySpace {
        DockGeometry.currentActivitySpace(
            activityDisplayID: settings.activityDisplayID,
            startPositionPercent: settings.startPositionPercent
        )
    }

    private func applyState(_ state: CatState) {
        stopWalk()
        switch state {
        case .transitioning:
            catWindow.hideBubble()
            iconController.showEmptyIcon()
            let pose = renderer.randomPose(for: .transition, fallback: .dialogue)
            catWindow.setImage(pose.image, mirrored: pose.mirrored)
            let point: CGPoint
            if shouldUseStartPositionForNextTransition {
                point = startPositionAnchor()
                shouldUseStartPositionForNextTransition = false
            } else {
                point = clampedCatPoint(stateMachine.position)
            }
            stateMachine.updateVisiblePosition(point)
            catWindow.show(at: point)
        case .walking:
            catWindow.hideBubble()
            iconController.showEmptyIcon()
            startWalk()
        case .resting:
            catWindow.hideBubble()
            iconController.showEmptyIcon()
            let pose = renderer.randomPose(for: .resting, fallback: .dialogue)
            RuntimeDiagnostics.record("resting imageLoaded=\(pose.image != nil) mirrored=\(pose.mirrored) position=\(stateMachine.position)")
            catWindow.setImage(pose.image, mirrored: pose.mirrored)
            let point = clampedCatPoint(stateMachine.position)
            stateMachine.updateLongDurationPosition(point)
            catWindow.show(at: point)
        case .dragged:
            catWindow.hideBubble()
            let pose = renderer.randomPose(for: .held, fallback: .dialogue)
            catWindow.setImage(pose.image, mirrored: pose.mirrored)
        case .dialogue(let type):
            let pose = renderer.randomPose(for: .dialogue)
            catWindow.setImage(pose.image, mirrored: pose.mirrored)
            let point = clampedCatPoint(stateMachine.position)
            stateMachine.updateVisiblePosition(point)
            catWindow.show(at: point)
            showReminder(type)
        case .outing(let phase):
            iconController.showEmptyIcon()
            applyOutingPhase(phase)
        }
    }

    private func showReminder(_ type: ReminderType) {
        catWindow.showBubble(
            message: type.message(settings: settings),
            primaryTitle: strings.done,
            secondaryTitle: strings.snoozeFiveMinutes,
            onPrimary: { [weak self] in
                guard let self else { return }
                self.reminderScheduler.complete(type)
                self.usageSessionTracker.recordCompletedReminder(type)
                self.saveUserDataBackup()
                self.catWindow.hideBubble()
                self.stateMachine.finishReminder()
                self.showNextQueuedAgentPresentationIfPossible()
            },
            onSecondary: { [weak self] in
                guard let self else { return }
                self.reminderScheduler.snooze(type)
                self.catWindow.hideBubble()
                self.stateMachine.finishReminder()
                self.showNextQueuedAgentPresentationIfPossible()
            }
        )
    }

    private func applyOutingPhase(_ phase: OutingPhase) {
        switch phase {
        case .asking:
            let pose = renderer.randomPose(for: .dialogue)
            catWindow.setImage(pose.image, mirrored: pose.mirrored)
            catWindow.show(at: clampedCatPoint(stateMachine.position))
            askOutingDuration()
        case .confirmingDeparture:
            catWindow.show(at: clampedCatPoint(stateMachine.position))
            showOutingDepartureResponse()
        case .leaving:
            startOutingWalkOut()
        case .away:
            catWindow.hide()
        case .returning:
            startOutingWalkIn()
        case .returned:
            let pose = renderer.randomPose(for: .dialogue)
            catWindow.setImage(pose.image, mirrored: pose.mirrored)
            showOutingReturnBubble()
        }
    }

    private func askOutingDuration() {
        catWindow.showInputBubble(
            message: strings.askOutingDuration(catName: settings.catName),
            value: "\(Int(settings.defaultOutingDuration / 60))",
            primaryTitle: strings.outingPrimary,
            secondaryTitle: strings.cancel,
            minuteUnit: strings.minuteUnit,
            onPrimary: { [weak self] value in
                self?.confirmOuting(minutesText: value)
            },
            onSecondary: { [weak self] in
                guard let self else { return }
                self.catWindow.hideBubble()
                self.stateMachine.enterRandomLongDurationState()
                self.showNextQueuedAgentPresentationIfPossible()
            }
        )
    }

    private func confirmOuting(minutesText: String) {
        let minutes = max(1, Int(minutesText) ?? Int(settings.defaultOutingDuration / 60))
        pendingOutingDuration = TimeInterval(minutes * 60)
        stateMachine.confirmOuting()
    }

    private func showOutingDepartureResponse() {
        catWindow.showBubble(
            message: strings.outingDeparture(settings: settings),
            primaryTitle: strings.ok,
            onPrimary: { [weak self] in
                self?.startConfirmedOuting()
            }
        )
    }

    private func startConfirmedOuting() {
        guard let duration = pendingOutingDuration else { return }
        catWindow.hideBubble()
        settings.activeOutingEndDate = Date().addingTimeInterval(duration)
        settings.activeOutingDuration = duration
        settingsStore.save(settings)
        suspendRemindersForOuting()
        scheduleOutingReturn(after: duration, plannedDuration: duration)
        pendingOutingDuration = nil
        stateMachine.departOuting()
    }

    private func returnFromOuting(drawReward: Bool = false, forceEvent: Bool = false, plannedDuration: TimeInterval? = nil) {
        outingTimer?.invalidate()
        if forceEvent {
            prepareOutingReturnEvent()
        } else if drawReward {
            prepareOutingReturnReward(plannedDuration: plannedDuration ?? settings.activeOutingDuration ?? settings.defaultOutingDuration)
        } else {
            pendingOutingReturnReward = nil
        }
        settings.activeOutingEndDate = nil
        settings.activeOutingDuration = nil
        settingsStore.save(settings)
        stateMachine.returnFromOuting()
    }

    private func scheduleOutingReturn(after interval: TimeInterval, plannedDuration: TimeInterval) {
        outingTimer?.invalidate()
        outingTimer = Timer.scheduledTimer(withTimeInterval: max(0.1, interval), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.returnFromOuting(drawReward: true, plannedDuration: plannedDuration)
            }
        }
    }

    private func prepareOutingReturnReward(plannedDuration: TimeInterval) {
        let generator = OutingRewardGenerator(catalog: outingCatalog)
        guard let reward = generator.reward(forOutingDuration: plannedDuration) else {
            pendingOutingReturnReward = nil
            return
        }

        recordOutingReward(reward)
    }

    private func prepareOutingReturnEvent() {
        let generator = OutingRewardGenerator(catalog: outingCatalog)
        guard let reward = generator.eventReward() else {
            pendingOutingReturnReward = nil
            return
        }

        recordOutingReward(reward)
    }

    private func recordOutingReward(_ reward: OutingReward) {
        pendingOutingReturnReward = reward
        switch reward {
        case .event:
            if collectableInventory.recentNewCollectableID != nil {
                collectableInventory.clearRecentNewMarker()
                collectableInventoryStore.save(collectableInventory)
            }
            usageSessionTracker.recordOutingEvent()
        case .collectable(let collectable):
            _ = collectableInventory.recordCollectable(collectable.id)
            collectableInventoryStore.save(collectableInventory)
            usageSessionTracker.recordOutingCollectable()
        }
    }

    private func showOutingReturnBubble() {
        switch pendingOutingReturnReward {
        case .event(let event):
            catWindow.showBubble(
                message: strings.outingReturnEvent(salutation: settings.userSalutation, event: event),
                primaryTitle: strings.welcomeBack,
                onPrimary: { [weak self] in
                    self?.finishOutingReturn()
                }
            )
        case .collectable(let collectable):
            catWindow.showImageBubble(
                message: strings.outingReturnCollectable(salutation: settings.userSalutation),
                image: collectableImage(collectable),
                imageTitle: strings.collectableName(collectable),
                primaryTitle: strings.receiveGift,
                onPrimary: { [weak self] in
                    self?.finishOutingReturn()
                }
            )
        case nil:
            catWindow.showBubble(
                message: strings.outingReturnPlain(salutation: settings.userSalutation),
                primaryTitle: strings.welcomeBack,
                onPrimary: { [weak self] in
                    self?.finishOutingReturn()
                }
            )
        }
    }

    private func finishOutingReturn() {
        pendingOutingReturnReward = nil
        catWindow.hideBubble()
        stateMachine.welcomeBack()
        restartRemindersAfterOuting()
        saveUserDataBackup()
        showNextQueuedAgentPresentationIfPossible()
    }

    private func configureAgentHTTPServer() {
        let server = AgentHTTPServer { [weak self] event in
            Task { @MainActor in
                self?.receiveAgentEvent(event)
            }
        }
        agentHTTPServer = server
        server.start()
    }

    private func receiveAgentEvent(_ event: AgentEvent) {
        let presentation = AgentEventPresenter.presentation(for: event, strings: strings)
        if canShowAgentPresentation(presentation) {
            showAgentPresentation(presentation)
        } else {
            agentEventQueue.enqueue(presentation)
        }
    }

    private func canShowAgentPresentation(_ presentation: AgentPresentation) -> Bool {
        if isProtectedAgentInteraction { return false }
        if activeAgentPresentation == nil { return canStartAgentPresentation(presentation) }
        return activeAgentPresentation?.priority == .low && presentation.priority == .high
    }

    private func canStartAgentPresentation(_ presentation: AgentPresentation) -> Bool {
        switch stateMachine.state {
        case .walking, .resting:
            return true
        case .transitioning:
            return presentation.priority == .high
        default:
            return false
        }
    }

    private func isActiveAgentPresentation(token: Int) -> Bool {
        activeAgentPresentation != nil && activeAgentPresentationToken == token
    }

    private var isProtectedAgentInteraction: Bool {
        if stateMachine.state.isOuting { return true }
        if case .dialogue = stateMachine.state, activeAgentPresentation == nil { return true }
        return false
    }

    private func showAgentPresentation(_ presentation: AgentPresentation) {
        activeAgentPresentationToken += 1
        let token = activeAgentPresentationToken
        activeAgentPresentation = presentation
        agentPresentationTimer?.invalidate()
        agentPatrolTimer?.invalidate()
        agentResumeTimer?.invalidate()
        stateScheduler.cancel()
        stateEndDate = nil
        stopWalk()
        catWindow.hideBubble()

        switch presentation.action {
        case .smallPatrol:
            showAgentSmallPatrol(presentation, token: token)
        case .comfortableFinish:
            showAgentDialogue(presentation, duration: 3.0, token: token)
        case .seriousAlert:
            showAgentDialogue(presentation, duration: 8.0, token: token)
        case .waitForUser:
            showAgentDialogue(presentation, duration: nil, token: token)
        case .turnToNotice:
            showAgentDialogue(presentation, duration: 3.0, token: token)
        }
    }

    private func showAgentSmallPatrol(_ presentation: AgentPresentation, token: Int) {
        let animation = renderer.animationFrames(\.walk)
        let sourceSize = stableWalkSourceSize()
        walkDirection = Bool.random() ? 1 : -1
        let point = clampedCatPoint(stateMachine.position)
        stateMachine.updateLongDurationPosition(point)
        catWindow.setImage(animation.frames.first ?? renderer.firstImage(for: .dialogue), mirrored: walkDirection < 0, sourceSize: sourceSize)
        catWindow.show(at: point)
        walkAnimator.start(animation: animation) { [weak self, animation] frameIndex in
            Task { @MainActor in
                guard let self else { return }
                guard self.isActiveAgentPresentation(token: token) else { return }
                self.catWindow.setImage(animation.frames[frameIndex], mirrored: self.walkDirection < 0, sourceSize: sourceSize)
            }
        }
        agentPatrolTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.isActiveAgentPresentation(token: token) else { return }
                self.stopWalk()
                self.showAgentDialogue(presentation, duration: 3.0, token: token)
            }
        }
    }

    private func showAgentDialogue(
        _ presentation: AgentPresentation,
        duration: TimeInterval?,
        token: Int
    ) {
        let showRestingPose = presentation.action == .comfortableFinish
        let pose = renderer.randomPose(for: .dialogue)
        let point = clampedCatPoint(stateMachine.position)
        stateMachine.updateLongDurationPosition(point)
        catWindow.setImage(pose.image, mirrored: pose.mirrored)
        catWindow.show(at: point)
        catWindow.showBubble(
            message: presentation.message,
            primaryTitle: strings.ok,
            onPrimary: { [weak self] in
                guard let self else { return }
                guard self.isActiveAgentPresentation(token: token) else { return }
                self.finishAgentPresentation(
                    token: token,
                    resumeWhenIdle: true,
                    showRestingPose: showRestingPose
                )
            }
        )
        if let duration {
            agentPresentationTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.isActiveAgentPresentation(token: token) else { return }
                    self.finishAgentPresentation(
                        token: token,
                        resumeWhenIdle: true,
                        showRestingPose: showRestingPose
                    )
                }
            }
        }
    }

    private func showAgentRestingPose() {
        let pose = renderer.randomPose(for: .resting, fallback: .dialogue)
        let point = clampedCatPoint(stateMachine.position)
        stateMachine.updateLongDurationPosition(point)
        catWindow.setImage(pose.image, mirrored: pose.mirrored)
        catWindow.show(at: point)
    }

    private func finishAgentPresentation(
        token: Int,
        resumeWhenIdle: Bool = true,
        showRestingPose: Bool = false
    ) {
        guard isActiveAgentPresentation(token: token) else { return }
        agentPresentationTimer?.invalidate()
        agentPresentationTimer = nil
        agentPatrolTimer?.invalidate()
        agentPatrolTimer = nil
        agentResumeTimer?.invalidate()
        agentResumeTimer = nil
        stopWalk()
        catWindow.hideBubble()
        activeAgentPresentation = nil
        if showRestingPose {
            showAgentRestingPose()
        }

        if showNextQueuedAgentPresentationIfPossible() {
            return
        }

        if resumeWhenIdle, showRestingPose {
            scheduleAgentResumeAfterSuccess()
        } else if resumeWhenIdle, canResumeAfterAgentPresentation {
            stateMachine.enterRandomLongDurationState()
        }
    }

    private var canResumeAfterAgentPresentation: Bool {
        switch stateMachine.state {
        case .walking, .resting, .transitioning:
            return true
        default:
            return false
        }
    }

    private func scheduleAgentResumeAfterSuccess() {
        guard stateMachine.state.isLongDuration, !isProtectedAgentInteraction else {
            return
        }
        let token = activeAgentPresentationToken
        agentResumeTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.agentResumeTimer = nil
                guard self.activeAgentPresentation == nil,
                      self.activeAgentPresentationToken == token,
                      self.stateMachine.state.isLongDuration,
                      !self.isProtectedAgentInteraction else {
                    return
                }
                self.stateMachine.enterRandomLongDurationState()
            }
        }
    }

    @discardableResult
    private func showNextQueuedAgentPresentationIfPossible() -> Bool {
        guard activeAgentPresentation == nil,
              !isProtectedAgentInteraction,
              let next = agentEventQueue.peekNext(),
              canStartAgentPresentation(next) else {
            return false
        }
        _ = agentEventQueue.popNext()
        showAgentPresentation(next)
        return true
    }

    private func collectableImage(_ collectable: OutingCollectable) -> NSImage? {
        NSImage(contentsOf: outingCatalog.imageURL(for: collectable))
    }

    private func startReminderPolling() {
        guard reminderTimer == nil else { return }
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.activeAgentPresentation == nil else { return }
                if let reminder = self.reminderScheduler.dueReminder(whenCatInLongDurationState: self.stateMachine.state.isLongDuration) {
                    _ = self.stateMachine.requestReminder(reminder)
                }
            }
        }
    }

    private func stopReminderPolling() {
        reminderTimer?.invalidate()
        reminderTimer = nil
    }

    private func suspendRemindersForOuting() {
        reminderScheduler.clear()
        stopReminderPolling()
    }

    private func restartRemindersAfterOuting() {
        reminderScheduler.restartTimersFromNow()
        if reminderScheduler.settings.remindersEnabled {
            startReminderPolling()
        }
    }

    private func scheduleStartupStretch() {
        startupTimer?.invalidate()
        startupTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.shouldUseStartPositionForNextTransition = true
                self.stateMachine.start()
            }
        }
    }

    private func restoreActiveOutingIfNeeded() -> Bool {
        guard settings.activeOutingEndDate != nil else {
            return false
        }

        suspendRemindersForOuting()
        stateMachine.restoreOutingAway()

        switch outingWakeResolver.resolution(
            endDate: settings.activeOutingEndDate,
            plannedDuration: settings.activeOutingDuration,
            defaultDuration: settings.defaultOutingDuration
        ) {
        case .noActiveOuting:
            return false
        case .reschedule(let remaining, let plannedDuration):
            scheduleOutingReturn(after: remaining, plannedDuration: plannedDuration)
        case .returnNow(let plannedDuration):
            returnFromOuting(drawReward: true, plannedDuration: plannedDuration)
        }
        return true
    }

    private func resolveActiveOutingAfterWake() {
        switch stateMachine.state {
        case .outing(.leaving), .outing(.away):
            break
        default:
            return
        }

        switch outingWakeResolver.resolution(
            endDate: settings.activeOutingEndDate,
            plannedDuration: settings.activeOutingDuration,
            defaultDuration: settings.defaultOutingDuration
        ) {
        case .noActiveOuting:
            return
        case .reschedule(let remaining, let plannedDuration):
            scheduleOutingReturn(after: remaining, plannedDuration: plannedDuration)
        case .returnNow(let plannedDuration):
            returnFromOuting(drawReward: true, plannedDuration: plannedDuration)
        }
    }

    private func startWalk() {
        let animation = renderer.animationFrames(\.walk)
        let sourceSize = stableWalkSourceSize()
        walkDirection = Bool.random() ? 1 : -1
        catWindow.setImage(animation.frames.first ?? renderer.firstImage(for: .dialogue), mirrored: walkDirection < 0, sourceSize: sourceSize)
        let start = clampedCatPoint(stateMachine.position)
        stateMachine.updateLongDurationPosition(start)
        catWindow.show(at: start)
        walkAnimator.start(animation: animation) { [weak self, animation] frameIndex in
            Task { @MainActor in
                guard let self else { return }
                self.catWindow.setImage(animation.frames[frameIndex], mirrored: self.walkDirection < 0, sourceSize: sourceSize)
            }
        }
        walkMovementTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceWalk()
            }
        }
    }

    private func advanceWalk() {
        guard case .walking = stateMachine.state else { return }
        let speed = CGFloat(settings.walkBaseSpeed)
        let walkRange = activitySpace.walkRangeForContent(width: catWindow.catFrameSize.width, scope: settings.catActivityScope)
        var nextX = stateMachine.position.x + walkDirection * speed / 30.0
        if nextX <= walkRange.lowerBound {
            nextX = walkRange.lowerBound
            walkDirection = 1
        } else if nextX >= walkRange.upperBound {
            nextX = walkRange.upperBound
            walkDirection = -1
        }
        let point = clampedCatPoint(CGPoint(x: nextX, y: stateMachine.position.y))
        stateMachine.updateLongDurationPosition(point)
        catWindow.setAnchor(point)
        catWindow.setMirrored(walkDirection < 0)
    }

    private func startOutingWalkOut() {
        let animation = renderer.animationFrames(\.walk)
        let sourceSize = stableWalkSourceSize()
        catWindow.setImage(animation.frames.first ?? renderer.firstImage(for: .dialogue), mirrored: false, sourceSize: sourceSize)
        let start = clampedCatPoint(stateMachine.position)
        stateMachine.updateOutingWalkPosition(start)
        walkDirection = 1
        catWindow.show(at: start)
        walkAnimator.start(animation: animation) { [weak self, animation] frameIndex in
            Task { @MainActor in
                guard let self else { return }
                self.catWindow.setImage(animation.frames[frameIndex], mirrored: false, sourceSize: sourceSize)
            }
        }
        walkMovementTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceOutingWalkOut()
            }
        }
    }

    private func advanceOutingWalkOut() {
        guard case .outing(.leaving) = stateMachine.state else { return }
        let speed = outingWalkSpeed
        let targetX = activitySpace.screenFrame.maxX + catWindow.catFrameSize.width
        var nextX = stateMachine.position.x + speed / 30.0
        if nextX >= targetX {
            nextX = targetX
            stopWalk()
            catWindow.hide()
            stateMachine.updateOutingWalkPosition(CGPoint(x: nextX, y: stateMachine.position.y))
            stateMachine.markAway()
            return
        }
        let point = CGPoint(x: nextX, y: stateMachine.position.y)
        stateMachine.updateOutingWalkPosition(point)
        catWindow.setAnchor(point)
        catWindow.setMirrored(false)
    }

    private func startOutingWalkIn() {
        let animation = renderer.animationFrames(\.walk)
        let sourceSize = stableWalkSourceSize()
        catWindow.setImage(animation.frames.first ?? renderer.firstImage(for: .dialogue), mirrored: true, sourceSize: sourceSize)
        let start = CGPoint(
            x: activitySpace.screenFrame.maxX + catWindow.catFrameSize.width,
            y: activitySpace.baselineY
        )
        stateMachine.updateOutingWalkPosition(start)
        walkDirection = -1
        catWindow.show(at: start)
        walkAnimator.start(animation: animation) { [weak self, animation] frameIndex in
            Task { @MainActor in
                guard let self else { return }
                self.catWindow.setImage(animation.frames[frameIndex], mirrored: true, sourceSize: sourceSize)
            }
        }
        walkMovementTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceOutingWalkIn()
            }
        }
    }

    private func advanceOutingWalkIn() {
        guard case .outing(.returning) = stateMachine.state else { return }
        let speed = outingWalkSpeed
        let target = outingReturnTarget()
        var nextX = stateMachine.position.x - speed / 30.0
        if nextX <= target.x {
            nextX = target.x
            let point = CGPoint(x: nextX, y: activitySpace.baselineY)
            stateMachine.updateOutingWalkPosition(point)
            catWindow.setAnchor(point)
            catWindow.setMirrored(true)
            stopWalk()
            stateMachine.finishReturnWalk()
            return
        }
        let point = CGPoint(x: nextX, y: activitySpace.baselineY)
        stateMachine.updateOutingWalkPosition(point)
        catWindow.setAnchor(point)
        catWindow.setMirrored(true)
    }

    private func stopWalk() {
        walkAnimator.stop()
        walkMovementTimer?.invalidate()
        walkMovementTimer = nil
    }

    private var outingWalkSpeed: CGFloat {
        CGFloat(settings.walkBaseSpeed) * 1.5
    }

    private func stableWalkSourceSize() -> CGSize {
        let sourcePack = renderer.walkAnimationSourcePack() ?? assetPack!
        let manifestSize = CGSize(width: sourcePack.manifest.canvasWidth, height: sourcePack.manifest.canvasHeight)
        if manifestSize.width > 0, manifestSize.height > 0 {
            return manifestSize
        }
        return renderer.animationFrames(\.walk).frames.reduce(CGSize.zero) { size, image in
            CGSize(width: max(size.width, image.size.width), height: max(size.height, image.size.height))
        }
    }

    private func outingReturnTarget() -> CGPoint {
        startPositionAnchor()
    }

    private func startPositionAnchor() -> CGPoint {
        anchorPoint(forCenterX: activitySpace.entrancePoint.x)
    }

    private func anchorPoint(forCenterX centerX: CGFloat) -> CGPoint {
        return activitySpace.dockEdgeClampedPoint(CGPoint(
            x: centerX - catWindow.catFrameSize.width / 2,
            y: activitySpace.baselineY
        ), contentWidth: catWindow.catFrameSize.width)
    }

    private func updateCurrentPositionPreservingState(_ point: CGPoint) {
        switch stateMachine.state {
        case .outing(.away):
            return
        case .outing(.leaving), .outing(.returning):
            stateMachine.updateOutingWalkPosition(point)
        default:
            stateMachine.updateVisiblePosition(point)
        }
        catWindow.setAnchor(point)
    }

    private func showRecallConfirmation() {
        guard case .outing(.away) = stateMachine.state else { return }
        let pose = renderer.randomPose(for: .dialogue)
        catWindow.setImage(pose.image, mirrored: pose.mirrored)
        catWindow.show(at: outingReturnTarget())
        catWindow.showBubble(
            message: strings.recallConfirmation(catName: settings.catName),
            primaryTitle: strings.confirm,
            secondaryTitle: strings.cancel,
            onPrimary: { [weak self] in
                guard let self else { return }
                self.catWindow.hideBubble()
                self.returnFromOuting(forceEvent: true)
            },
            onSecondary: { [weak self] in
                guard let self else { return }
                self.catWindow.hideBubble()
                self.catWindow.hide()
            }
        )
    }

    private func petCat() {
        guard activeAgentPresentation == nil else { return }
        switch stateMachine.state {
        case .resting:
            let pose = renderer.randomPose(for: .resting, fallback: .dialogue)
            catWindow.setImage(pose.image, mirrored: pose.mirrored)
            let point = clampedCatPoint(stateMachine.position)
            stateMachine.updateLongDurationPosition(point)
            catWindow.show(at: point)
        case .walking:
            walkDirection *= -1
            catWindow.setMirrored(walkDirection < 0)
        default:
            return
        }
    }

    private func clampedCatPoint(_ point: CGPoint) -> CGPoint {
        activitySpace.clampedPoint(point, contentSize: catWindow.catFrameSize, scope: settings.catActivityScope)
    }

    private func outingWalkOutDragPoint(_ point: CGPoint) -> CGPoint {
        if settings.catActivityScope == .desktop {
            let visibleRange = activitySpace.desktopWalkRangeForContent(width: catWindow.catFrameSize.width)
            let targetX = activitySpace.screenFrame.maxX + catWindow.catFrameSize.width
            let yRange = activitySpace.desktopYRangeForContent(height: catWindow.catFrameSize.height)
            return CGPoint(
                x: GeometryUtils.clamped(point.x, to: visibleRange.lowerBound ... targetX),
                y: GeometryUtils.clamped(point.y, to: yRange)
            )
        }
        let visibleRange = activitySpace.dockEdgeWalkRangeForContent(width: catWindow.catFrameSize.width)
        let targetX = activitySpace.screenFrame.maxX + catWindow.catFrameSize.width
        return CGPoint(
            x: GeometryUtils.clamped(point.x, to: visibleRange.lowerBound ... targetX),
            y: activitySpace.baselineY
        )
    }

    private func updateStateMachineParameters() {
        stateMachine.updateParameters(
            walkingDurationRange: durationRange(
                minimum: settings.walkDurationMinimum,
                maximum: settings.walkDurationMaximum,
                fallback: AppSettings.defaults.walkDurationMinimum ... AppSettings.defaults.walkDurationMaximum
            ),
            restingDurationRange: durationRange(
                minimum: settings.restDurationMinimum,
                maximum: settings.restDurationMaximum,
                fallback: AppSettings.defaults.restDurationMinimum ... AppSettings.defaults.restDurationMaximum
            )
        )
    }

    private func reloadSelectedAssetPack() {
        assetPack = assetLoader.loadSelectedPack(selectedID: settings.selectedAssetPackID)
        renderer = PoseRenderer(pack: assetPack, fallbackPack: defaultAssetPack)
        RuntimeDiagnostics.record("reloaded assetPack id=\(assetPack.id) root=\(assetPack.rootURL.path)")
        iconController.updateIconSource(appIconStore.prepareActiveIconSource(selectedPack: assetPack))
        settingsWindowController.update(dialogueImage: renderer.randomPose(for: .dialogue).image)
    }

    private func durationRange(
        minimum: TimeInterval,
        maximum: TimeInterval,
        fallback: ClosedRange<TimeInterval>
    ) -> ClosedRange<TimeInterval> {
        let lower = max(1, minimum)
        let upper = max(1, maximum)
        guard lower <= upper else { return fallback }
        return lower ... upper
    }

    @objc private func startOutingFromMenu() {
        beginOutingPromptIfAvailable()
    }

    @objc private func petFromMenu() {
        petCat()
    }

    @objc private func openSettingsFromMenu() {
        showSettings()
    }

    @objc private func quitFromMenu() {
        NSApplication.shared.terminate(nil)
    }

    private func beginOutingPromptIfAvailable() {
        guard activeAgentPresentation == nil else { return }
        stateMachine.beginOutingPrompt()
    }
}

private final class CallbackTarget: NSObject {
    private let callback: () -> Void

    init(_ callback: @escaping () -> Void) {
        self.callback = callback
    }

    @objc func invoke() {
        callback()
    }
}
