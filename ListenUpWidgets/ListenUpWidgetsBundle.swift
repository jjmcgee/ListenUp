import WidgetKit
import SwiftUI

@main
struct ListenUpWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PlayerWidget()
        TimeListenedWidget()
    }
}
