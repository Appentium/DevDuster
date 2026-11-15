import Foundation
import SweepCore

let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperIdentity.machServiceName)
listener.delegate = delegate
listener.resume()
dispatchMain()
