final class DeepLinkHandler {
    static let shared = DeepLinkHandler()
    
    private init() {}
    
    func handle(url: URL) {
        guard url.host == "places",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let latString = components.queryItems?.first(where: { $0.name == "lat" })?.value,
              let lonString = components.queryItems?.first(where: { $0.name == "lon" })?.value,
              let lat = Double(latString),
              let lon = Double(lonString) else {
            return
        }
        
        let name = components.queryItems?.first(where: { $0.name == "name" })?.value
        
        DispatchQueue.main.async {
            self.navigateToPlacesTab(lat: lat, lon: lon, name: name)
        }
    }
    
    func navigateToPlacesTab(lat: Double, lon: Double, name: String?) {
        guard let window = UIApplication.shared.windows.first,
              let tabBarController = window.rootViewController as? UITabBarController,
              let viewControllers = tabBarController.viewControllers else {
            return
        }
        
        for viewController in viewControllers {
            if let nav = viewController as? UINavigationController,
               let placesVC = nav.viewControllers.first(where: { $0 is PlacesViewController }) as? PlacesViewController {
                
                tabBarController.selectedViewController = nav
                
                placesVC.isWaitingForDeepLinkSearch = true
                // Delay search until the runloop lets the view fully appear
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    placesVC.triggerSearchForCoordinates(
                        CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        name: name
                    )
                }
                
                return
            }
        }
    }
}
