import Combine
import SwiftUI

extension BlindOrderStatusViewModel {
    // MARK: - App-lifetime realtime routing

    func subscribeToRealtimeCoordinator(appState: AppState) {
        cancellables.removeAll()
        let coordinator = appState.realtimeCoordinator
        coordinator.$pendingOrderRefreshIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] orderIDs in
                guard let self, let orderID = self.activeOrderId, orderIDs.contains(orderID) else { return }
                Task { await self.loadOrder(orderId: orderID, speakChanges: true) }
            }
            .store(in: &cancellables)

        coordinator.statusUpdatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self,
                      let current = self.order,
                      current.orderId == update.orderId else { return }
                self.apply(
                    current.replacingStatus(with: update.toStatus),
                    speakChanges: true
                )
                self.isLoading = false
                self.errorMessage = nil
            }
            .store(in: &cancellables)

        coordinator.peerLocationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sample in self?.handleVolunteerLocationUpdate(sample) }
            .store(in: &cancellables)

        if let orderID = activeOrderId,
           let sample = coordinator.latestPeerLocation(orderID: orderID, ownerRole: .volunteer) {
            handleVolunteerLocationUpdate(sample)
        }
    }
}
