import Foundation
import UIKit
import AsyncDisplayKit
import Postbox
import Display
import SwiftSignalKit
import TelegramPresentationData

private let searchBarFont = Font.regular(17.0)

class ChatListSearchItem: ListViewItem {
    let selectable: Bool = false
    
    let theme: PresentationTheme
    let isEnabled: Bool
    private let placeholder: String
    private let activate: () -> Void
    
    init(theme: PresentationTheme, isEnabled: Bool = true, placeholder: String, activate: @escaping () -> Void) {
        self.theme = theme
        self.isEnabled = isEnabled
        self.placeholder = placeholder
        self.activate = activate
    }
    
    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ChatListSearchItemNode()
            node.placeholder = self.placeholder
            
            let makeLayout = node.asyncLayout()
            var nextIsPinned = false
            if let nextItem = nextItem as? ChatListItem, nextItem.index.pinningIndex != nil {
                nextIsPinned = true
            }
            let (layout, apply) = makeLayout(self, params, nextIsPinned, self.isEnabled)
            
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            
            node.activate = self.activate
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in
                        apply(false)
                    })
                })
            }
        }
    }
    
    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? ChatListSearchItemNode {
                nodeValue.placeholder = self.placeholder
                let layout = nodeValue.asyncLayout()
                async {
                    var nextIsPinned = false
                    if let nextItem = nextItem as? ChatListItem, nextItem.index.pinningIndex != nil {
                        nextIsPinned = true
                    }
                    let (nodeLayout, apply) = layout(self, params, nextIsPinned, self.isEnabled)
                    Queue.mainQueue().async {
                        completion(nodeLayout, { _ in
                            apply(animation.isAnimated)
                        })
                    }
                }
            }
        }
    }
}

class ChatListSearchItemNode: ListViewItemNode {
    let searchBarNode: SearchBarPlaceholderNode
    private var disabledOverlay: ASDisplayNode?
    var placeholder: String?
    
    fileprivate var activate: (() -> Void)? {
        didSet {
            self.searchBarNode.activate = self.activate
        }
    }
    
    required init() {
        self.searchBarNode = SearchBarPlaceholderNode(fieldStyle: .modern)
        
        super.init(layerBacked: false, dynamicBounce: false)
        
        self.addSubnode(self.searchBarNode)
    }
    
    override func layoutForParams(_ params: ListViewItemLayoutParams, item: ListViewItem, previousItem: ListViewItem?, nextItem: ListViewItem?) {
        let makeLayout = self.asyncLayout()
        var nextIsPinned = false
        if let nextItem = nextItem as? ChatListItem, nextItem.index.pinningIndex != nil {
            nextIsPinned = true
        }
        let (layout, apply) = makeLayout(item as! ChatListSearchItem, params, nextIsPinned, (item as! ChatListSearchItem).isEnabled)
        apply(false)
        self.contentSize = layout.contentSize
        self.insets = layout.insets
    }
    
    func asyncLayout() -> (_ item: ChatListSearchItem, _ params: ListViewItemLayoutParams, _ nextIsPinned: Bool, _ isEnabled: Bool) -> (ListViewItemNodeLayout, (Bool) -> Void) {
        let searchBarNodeLayout = self.searchBarNode.asyncLayout()
        let placeholder = self.placeholder
        
        return { item, params, nextIsPinned, isEnabled in
            let baseWidth = params.width - params.leftInset - params.rightInset
            
            let backgroundColor = nextIsPinned ? item.theme.chatList.pinnedItemBackgroundColor : item.theme.chatList.itemBackgroundColor
            let placeholderColor = item.theme.rootController.activeNavigationSearchBar.inputPlaceholderTextColor
            
            let (_, searchBarApply) = searchBarNodeLayout(NSAttributedString(string: placeholder ?? "", font: searchBarFont, textColor: placeholderColor), CGSize(width: baseWidth - 20.0, height: 36.0), 1.0, placeholderColor, nextIsPinned ? item.theme.chatList.pinnedSearchBarColor : item.theme.chatList.regularSearchBarColor, backgroundColor, .immediate)
            
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: 54.0), insets: UIEdgeInsets())
            
            return (layout, { [weak self] animated in
                if let strongSelf = self {
                    let transition: ContainedViewLayoutTransition
                    if animated {
                        transition = .animated(duration: 0.3, curve: .easeInOut)
                    } else {
                        transition = .immediate
                    }
                    
                    let searchBarFrame = CGRect(origin: CGPoint(x: params.leftInset + 10.0, y: 8.0), size: CGSize(width: baseWidth - 20.0, height: 36.0))
                    strongSelf.searchBarNode.frame = searchBarFrame
                    searchBarApply()
                    
                    strongSelf.searchBarNode.bounds = CGRect(origin: CGPoint(), size: CGSize(width: baseWidth - 20.0, height: 36.0))
                    
                    if !item.isEnabled {
                        if strongSelf.disabledOverlay == nil {
                            let disabledOverlay = ASDisplayNode()
                            strongSelf.addSubnode(disabledOverlay)
                            strongSelf.disabledOverlay = disabledOverlay
                            if animated {
                                disabledOverlay.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
                            }
                        }
                        if let disabledOverlay = strongSelf.disabledOverlay {
                            disabledOverlay.backgroundColor = backgroundColor.withAlphaComponent(0.4)
                            disabledOverlay.frame = searchBarFrame
                        }
                    } else if let disabledOverlay = strongSelf.disabledOverlay {
                        strongSelf.disabledOverlay = nil
                        if animated {
                            disabledOverlay.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false, completion: { [weak disabledOverlay] _ in
                                disabledOverlay?.removeFromSupernode()
                            })
                        } else {
                            disabledOverlay.removeFromSupernode()
                        }
                    }
                    
                    transition.updateBackgroundColor(node: strongSelf, color: backgroundColor)
                }
            })
        }
    }
}
