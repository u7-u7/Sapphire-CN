import Foundation

/// 弹窗暂时保留当前刘海实例，不改变用户的固定状态。
/// 使用 owner 集合允许重复关闭回调，也避免一个弹窗释放另一个弹窗的保留状态。
struct NotchPopoverPresentationState {
    private var owners: Set<UUID> = []
    var holdsExpansion: Bool { !owners.isEmpty }

    mutating func setPresented(_ isPresented: Bool, owner: UUID) {
        if isPresented { owners.insert(owner) }
        else { owners.remove(owner) }
    }

    mutating func reset() { owners.removeAll() }
}
