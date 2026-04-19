import Foundation
import UniformTypeIdentifiers
import SGItemListUI
import UndoUI
import AccountContext
import Display
import TelegramCore
import Postbox
import ItemListUI
import SwiftSignalKit
import TelegramPresentationData
import PresentationDataUtils
import TelegramUIPreferences
import SettingsUI

// Optional
import SGSimpleSettings
import SGLogging

private enum SGProControllerSection: Int32, SGItemListSection {
    case base
    case appearance
    case notifications
    case footer
}

private enum SGProDisclosureLink: String {
    case sessionBackupManager
    case messageFilter
    case appIcons
    case appBages
}

private enum SGProToggles: String {
    case inputToolbar
}

private enum SGProOneFromManySetting: String {
    case pinnedMessageNotifications
    case mentionsAndRepliesNotifications
}

private enum SGProAction {
    case resetIAP
    case checkUpdate // 🚀 [SG-Pro 注入 1/3]: 注册检查更新事件
}

private typealias SGProControllerEntry = SGItemListUIEntry<SGProControllerSection, SGProToggles, AnyHashable, SGProOneFromManySetting, SGProDisclosureLink, SGProAction>

private func SGProControllerEntries(presentationData: PresentationData) -> [SGProControllerEntry] {
    var entries: [SGProControllerEntry] = []
    let lang = presentationData.strings.baseLanguageCode
    
    let id = SGItemListCounter()
    
    entries.append(.disclosure(id: id.count, section: .base, link: .sessionBackupManager, text: "SessionBackup.Title".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .base, link: .messageFilter, text: "MessageFilter.Title".i18n(lang)))
    entries.append(.toggle(id: id.count, section: .base, settingName: .inputToolbar, value: SGSimpleSettings.shared.inputToolbar, text: "InputToolbar.Title".i18n(lang), enabled: true))
    
    // 🚀 [SG-Pro 注入 2/3]: 在基础设置栏里添加 OTA 更新按钮
    entries.append(.action(id: id.count, section: .base, actionType: .checkUpdate, text: "🚀 检测并更新 SG-Pro (OTA)", kind: .generic))
    
    entries.append(.header(id: id.count, section: .notifications, text: presentationData.strings.Notifications_Title.uppercased(), badge: nil))
    entries.append(.oneFromManySelector(id: id.count, section: .notifications, settingName: .pinnedMessageNotifications, text: "Notifications.PinnedMessages.Title".i18n(lang), value: "Notifications.PinnedMessages.value.\(SGSimpleSettings.shared.pinnedMessageNotifications)".i18n(lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .notifications, settingName: .mentionsAndRepliesNotifications, text: "Notifications.MentionsAndReplies.Title".i18n(lang), value: "Notifications.MentionsAndReplies.value.\(SGSimpleSettings.shared.mentionsAndRepliesNotifications)".i18n(lang), enabled: true))
    entries.append(.header(id: id.count, section: .appearance, text: presentationData.strings.Appearance_Title.uppercased(), badge: nil))
    entries.append(.disclosure(id: id.count, section: .appearance, link: .appIcons, text: presentationData.strings.Appearance_AppIcon))
    entries.append(.disclosure(id: id.count, section: .appearance, link: .appBages, text: "AppBadge.Title".i18n(lang)))
    entries.append(.notice(id: id.count, section: .appearance, text: "AppBadge.Notice".i18n(lang)))

    #if DEBUG
    entries.append(.action(id: id.count, section: .footer, actionType: .resetIAP, text: "Reset Pro", kind: .destructive))
    #endif
    
    return entries
}

public func okUndoController(_ text: String, _ presentationData: PresentationData) -> UndoOverlayController {
    return UndoOverlayController(presentationData: presentationData, content: .succeed(text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
}

public func sgProController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

    let simplePromise = ValuePromise(true, ignoreRepeated: false)
    
    let arguments = SGItemListArguments<SGProToggles, AnyHashable, SGProOneFromManySetting, SGProDisclosureLink, SGProAction>(context: context, setBoolValue: { toggleName, value in
        switch toggleName {
            case .inputToolbar:
                SGSimpleSettings.shared.inputToolbar = value
        }
    }, setOneFromManyValue: { setting in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        
        switch (setting) {
            case .pinnedMessageNotifications:
                let setAction: (String) -> Void = { value in
                    SGSimpleSettings.shared.pinnedMessageNotifications = value
                    SGSimpleSettings.shared.synchronizeShared()
                    simplePromise.set(true)
                }

                for value in SGSimpleSettings.PinnedMessageNotificationsSettings.allCases {
                    items.append(ActionSheetButtonItem(title: "Notifications.PinnedMessages.value.\(value.rawValue)".i18n(lang), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
            case .mentionsAndRepliesNotifications:
                let setAction: (String) -> Void = { value in
                    SGSimpleSettings.shared.mentionsAndRepliesNotifications = value
                    SGSimpleSettings.shared.synchronizeShared()
                    simplePromise.set(true)
                }

                for value in SGSimpleSettings.MentionsAndRepliesNotificationsSettings.allCases {
                    items.append(ActionSheetButtonItem(title: "Notifications.MentionsAndReplies.value.\(value.rawValue)".i18n(lang), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
        }
        
        actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])])
        presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }, openDisclosureLink: { link in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        switch (link) {
            case .sessionBackupManager:
                pushControllerImpl?(sgSessionBackupManagerController(context: context, presentationData: presentationData))
            case .messageFilter:
                pushControllerImpl?(sgMessageFilterController(presentationData: presentationData))
            case .appIcons:
                pushControllerImpl?(themeSettingsController(context: context, focusOnItemTag: .icon))
            case .appBages:
                if #available(iOS 14.0, *) {
                    pushControllerImpl?(sgAppBadgeSettingsController(context: context, presentationData: presentationData))
                } else {
                    presentControllerImpl?(context.sharedContext.makeSGUpdateIOSController(), nil)
                }
        }
    }, action: { action in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        switch action {
            case .resetIAP:
                let updateSettingsSignal = updateSGStatusInteractively(accountManager: context.sharedContext.accountManager, { status in
                    var status = status
                    status.status = SGStatus.default.status
                    SGSimpleSettings.shared.primaryUserId = ""
                    return status
                })
                let _ = (updateSettingsSignal |> deliverOnMainQueue).start(next: {
                    presentControllerImpl?(UndoOverlayController(
                        presentationData: presentationData,
                        content: .info(title: nil, text: "Status reset completed. You can now restore purchases.", timeout: nil, customUndoText: nil),
                        elevatedLayout: false,
                        action: { _ in return false }
                    ),
                    nil)
                })
            
            // 🚀 [SG-Pro 注入 3/3]: 处理点击检查更新的核心网络与弹窗逻辑
            case .checkUpdate:
                // 先弹出一个提示，告诉用户正在拉取
                presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "正在请求 GitHub 获取最新版本...", timeout: 2, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), nil)
                
                let url = URL(string: "https://api.github.com/repos/ac54u/Swiftgram-Pro/releases/latest")!
                var request = URLRequest(url: url)
                request.timeoutInterval = 8.0 // 8秒超时
                
                URLSession.shared.dataTask(with: request) { data, response, error in
                    DispatchQueue.main.async {
                        guard let data = data, error == nil else {
                            presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "网络超时，请检查代理或网络连接。", timeout: 3, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), nil)
                            return
                        }
                        
                        do {
                            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                               let latestVersion = json["tag_name"] as? String,
                               let assets = json["assets"] as? [[String: Any]],
                               let ipaAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".ipa") == true }),
                               let downloadUrl = ipaAsset["browser_download_url"] as? String {
                                
                                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
                                
                                // 简单判断是否大于当前版本
                                if latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                                    // 发现新版本！弹出极客风格的确认框
                                    let actionSheet = ActionSheetController(presentationData: presentationData)
                                    actionSheet.setItemGroups([
                                        ActionSheetItemGroup(items: [
                                            ActionSheetButtonItem(title: "🔥 发现新版本: \(latestVersion)", color: .accent, action: { [weak actionSheet] in
                                                actionSheet?.dismissAnimated()
                                            }),
                                            ActionSheetButtonItem(title: "⚡️ 通过 TrollStore 静默安装", color: .constructive, action: { [weak actionSheet] in
                                                actionSheet?.dismissAnimated()
                                                // 组装巨魔专属直装链接
                                                if let encodedUrl = downloadUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                                                   let trollStoreUrl = URL(string: "trollstore://install?url=\(encodedUrl)") {
                                                    if UIApplication.shared.canOpenURL(trollStoreUrl) {
                                                        UIApplication.shared.open(trollStoreUrl)
                                                    } else {
                                                        // 没装巨魔，跳去浏览器下载
                                                        UIApplication.shared.open(URL(string: "https://github.com/ac54u/Swiftgram-Pro/releases/latest")!)
                                                    }
                                                }
                                            })
                                        ]),
                                        ActionSheetItemGroup(items: [
                                            ActionSheetButtonItem(title: "暂不更新", color: .accent, font: .bold, action: { [weak actionSheet] in
                                                actionSheet?.dismissAnimated()
                                            })
                                        ])
                                    ])
                                    presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
                                } else {
                                    presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "当前已经是最新版 (\(currentVersion))，无需更新。", timeout: 3, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), nil)
                                }
                            } else {
                                presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "API 返回格式异常，未找到 IPA 文件。", timeout: 3, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), nil)
                            }
                        } catch {
                            presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "JSON 解析失败。", timeout: 2, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), nil)
                        }
                    }
                }.resume()
        }
    })
    
    let signal = combineLatest(context.sharedContext.presentationData, simplePromise.get())
    |> map { presentationData, _ ->  (ItemListControllerState, (ItemListNodeState, Any)) in
        
        let entries = SGProControllerEntries(presentationData: presentationData)
        
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Swiftgram Pro"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: /*focusOnItemTag*/ nil, initialScrollToItem: nil /* scrollToItem*/ )
        
        return (controllerState, (listState, arguments))
    }
    
    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    // Workaround
    let _ = pushControllerImpl
    
    return controller
}