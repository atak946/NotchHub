import Foundation
import Observation

/// Facade owning the Docker, endpoint and local LLM monitors.
@MainActor
@Observable
final class DevOpsMonitors {
    let docker: DockerMonitor
    let endpoints: EndpointMonitor
    let localLLM: LocalLLMMonitor

    init(alerts: NotchAlertCenter, defaults: UserDefaults = .standard) {
        docker = DockerMonitor(alerts: alerts, defaults: defaults)
        endpoints = EndpointMonitor(alerts: alerts, defaults: defaults)
        localLLM = LocalLLMMonitor(alerts: alerts, defaults: defaults)
    }

    /// Designated init for tests and custom wiring.
    init(docker: DockerMonitor, endpoints: EndpointMonitor, localLLM: LocalLLMMonitor) {
        self.docker = docker
        self.endpoints = endpoints
        self.localLLM = localLLM
    }

    /// Idempotent; each monitor only runs while its own enable toggle is on.
    func start() {
        docker.start()
        endpoints.start()
        localLLM.start()
    }

    func stop() {
        docker.stop()
        endpoints.stop()
        localLLM.stop()
    }

    var hasCompactIndicator: Bool {
        docker.hasCompactIndicator || endpoints.hasCompactIndicator
    }
}
