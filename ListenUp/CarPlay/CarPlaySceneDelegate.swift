#if canImport(CarPlay)
import CarPlay
import UIKit

/// CarPlay application scene delegate managing connection to the car head unit.
@MainActor
public final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    
    public var interfaceController: CPInterfaceController?
    private var templateManager: CarPlayTemplateManager?
    
    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        let manager = CarPlayTemplateManager(interfaceController: interfaceController)
        self.templateManager = manager
        manager.start()
    }
    
    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        templateManager?.stop()
        self.templateManager = nil
        self.interfaceController = nil
    }
}
#endif
