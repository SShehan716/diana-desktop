import AppKit
import DianaCore
@preconcurrency import MetalKit
import RealityKit
import SwiftUI

enum DianaResources {
    static func modelURL(_ motion: PetMotion) throws -> URL {
        let name = "Diana-\(motion.rawValue)"
        if let url = Bundle.main.url(forResource: name, withExtension: "usdz", subdirectory: "Models") {
            return url
        }
        // Bundle.module traps when the packaged app has no SwiftPM resource bundle.
        for base in [Bundle.main.resourceURL, Bundle.main.bundleURL].compactMap({ $0 }) {
            let bundle = Bundle(url: base.appendingPathComponent("Diana_DianaApp.bundle"))
            if let url = bundle?.url(
                forResource: name, withExtension: "usdz", subdirectory: "Resources/Models")
            {
                return url
            }
        }
        throw NSError(
            domain: "Diana", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Diana’s \(motion.rawValue) model is missing from the app bundle."
            ])
    }
}

@MainActor final class DianaAssetLibrary {
    static let shared = DianaAssetLibrary()
    private var entities: [PetMotion: Entity] = [:]
    private var loads: [PetMotion: Task<Entity, Error>] = [:]
    private var environmentLoad: Task<EnvironmentResource, Error>?
    func studioEnvironment() async throws -> EnvironmentResource {
        if let environmentLoad { return try await environmentLoad.value }
        let load = Task { @MainActor in
            let space = CGColorSpace(name: CGColorSpace.linearSRGB)!
            let context = CGContext(
                data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 64 * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(colorSpace: space, components: [0.65, 0.67, 0.72, 1])!)
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
            return try await EnvironmentResource(
                equirectangular: context.makeImage()!, withName: "DianaStudio")
        }
        environmentLoad = load
        return try await load.value
    }
    func instance(for motion: PetMotion) async throws -> Entity {
        if let entity = entities[motion] { return entity.clone(recursive: true) }
        let load: Task<Entity, Error>
        if let pending = loads[motion] {
            load = pending
        } else {
            load = Task { @MainActor in try await Entity(contentsOf: DianaResources.modelURL(motion)) }
            loads[motion] = load
        }
        do {
            let entity = try await load.value
            entities[motion] = entity
            loads[motion] = nil
            return entity.clone(recursive: true)
        } catch {
            loads[motion] = nil
            throw error
        }
    }
}

final class PetMetalView: MTKView {
    var draggable = false
    var onDragEnd: (() -> Void)?
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {
        if draggable {
            window?.performDrag(with: event)
            onDragEnd?()
        } else {
            super.mouseDown(with: event)
        }
    }
}

// Retain the drawable until RealityKit finishes rendering on the GPU.
private final class DrawableTicket: @unchecked Sendable {
    let drawable: any CAMetalDrawable
    let semaphore: DispatchSemaphore
    init(_ drawable: any CAMetalDrawable, semaphore: DispatchSemaphore) {
        self.drawable = drawable
        self.semaphore = semaphore
    }
    func present() {
        drawable.present()
        semaphore.signal()
    }
}

struct DianaScene: NSViewRepresentable {
    var motion: PetMotion = .idle
    var replay = 0
    var reducedMotion = false
    var lowPower = true
    var speed = 1.0
    var yaw: Double = -0.10
    var draggable = false
    var onDragEnd: (() -> Void)? = nil
    var onReady: (() -> Void)? = nil
    var onError: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> PetMetalView {
        let view = PetMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.framebufferOnly = false
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        view.setAccessibilityLabel("Animated 3D companion")
        view.autoResizeDrawable = true
        view.preferredFramesPerSecond = lowPower ? 15 : 30
        view.delegate = context.coordinator
        context.coordinator.view = view
        context.coordinator.setup(onError: onError)
        return view
    }
    func updateNSView(_ view: PetMetalView, context: Context) {
        view.draggable = draggable
        view.onDragEnd = onDragEnd
        context.coordinator.onReady = onReady
        context.coordinator.onError = onError
        context.coordinator.update(
            motion: motion, replay: replay, reduced: reducedMotion, speed: speed, yaw: yaw)
        view.preferredFramesPerSecond =
            lowPower || ProcessInfo.processInfo.isLowPowerModeEnabled ? (motion == .idle ? 8 : 15) : 30
    }
    static func dismantleNSView(_ view: PetMetalView, coordinator: Coordinator) {
        view.isPaused = true
        view.delegate = nil
        coordinator.loadTask?.cancel()
        coordinator.lightingTask?.cancel()
        coordinator.renderer?.entities.removeAll()
    }

    @MainActor final class Coordinator: NSObject, MTKViewDelegate {
        weak var view: PetMetalView?
        var renderer: RealityRenderer?
        var root: Entity?
        var controller: AnimationPlaybackController?
        var loadTask: Task<Void, Never>?
        var lightingTask: Task<Void, Never>?
        var requested: PetMotion?
        var requestedReplay = -1
        var reduced = false
        var speed: Double = 1
        var yaw: Double = -0.10
        var previousTime: TimeInterval = 0
        var needsStillFrame = true
        var onReady: (() -> Void)?
        var onError: ((String) -> Void)?
        private let inflight = DispatchSemaphore(value: 2)
        func setup(onError: ((String) -> Void)?) {
            do {
                let renderer = try RealityRenderer()
                self.renderer = renderer
                renderer.cameraSettings.colorBackground = .color(NSColor.clear.cgColor)
                renderer.cameraSettings.antialiasing = .multisample4X
                let camera = Entity()
                var projection = OrthographicCameraComponent()
                projection.near = 0.01
                projection.far = 100
                projection.scale = 1.28
                projection.scaleDirection = .vertical
                camera.components.set(projection)
                camera.position = [0, 1.02, 4]
                camera.look(at: [0, 1.02, 0], from: camera.position, relativeTo: nil)
                renderer.entities.append(camera)
                renderer.activeCamera = camera
                for (position, intensity, color) in [
                    (SIMD3<Float>(-2, 3, 3), Float(1600), NSColor(red: 1, green: 0.94, blue: 0.88, alpha: 1)),
                    (SIMD3<Float>(2, 2, 1), Float(900), NSColor(red: 0.80, green: 0.88, blue: 1, alpha: 1)),
                    (SIMD3<Float>(1, 3, -3), Float(1800), NSColor.white),
                ] {
                    let light = DirectionalLight()
                    light.light.intensity = intensity
                    light.light.color = color
                    light.look(at: [0, 1, 0], from: position, relativeTo: nil)
                    renderer.entities.append(light)
                }
                lightingTask = Task { @MainActor [weak self] in
                    do {
                        let resource = try await DianaAssetLibrary.shared.studioEnvironment()
                        guard !Task.isCancelled else { return }
                        self?.renderer?.lighting.resource = resource
                        self?.renderer?.lighting.intensityExponent = 0.1
                        self?.needsStillFrame = true
                    } catch { onError?("Studio lighting couldn’t load: \(error.localizedDescription)") }
                }
            } catch { onError?(error.localizedDescription) }
        }
        func update(motion: PetMotion, replay: Int, reduced: Bool, speed: Double, yaw: Double) {
            if self.yaw != yaw { needsStillFrame = true }
            self.speed = speed * (motion == .run ? 1.25 : 1)
            self.yaw = yaw
            if self.reduced != reduced {
                self.reduced = reduced
                if reduced {
                    controller?.time = 0.2
                    controller?.pause()
                } else {
                    controller?.resume()
                }
                needsStillFrame = true
            }
            root?.orientation = simd_quatf(angle: Float(yaw), axis: [0, 1, 0])
            controller?.speed = Float(self.speed)
            guard requested != motion || requestedReplay != replay else { return }
            requested = motion
            requestedReplay = replay
            loadTask?.cancel()
            loadTask = Task { @MainActor [weak self] in
                do {
                    let entity = try await DianaAssetLibrary.shared.instance(for: motion)
                    guard !Task.isCancelled, let self, self.requested == motion, let renderer = self.renderer
                    else { return }
                    if let root = self.root { renderer.entities.remove(root) }
                    self.root = entity
                    entity.orientation = simd_quatf(angle: Float(self.yaw), axis: [0, 1, 0])
                    renderer.entities.append(entity)
                    guard let animation = entity.availableAnimations.first else {
                        throw NSError(
                            domain: "Diana", code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "This character has no playable animation."]
                        )
                    }
                    let resource = [.idle, .run].contains(motion) ? animation.repeat() : animation
                    self.controller = entity.playAnimation(resource, transitionDuration: 0)
                    self.controller?.speed = Float(self.speed)
                    if self.reduced {
                        self.controller?.time = 0.2
                        self.controller?.pause()
                    }
                    self.needsStillFrame = true
                    self.onReady?()
                } catch { if !Task.isCancelled { self?.onError?(error.localizedDescription) } }
            }
        }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { needsStillFrame = true }
        func draw(in view: MTKView) {
            guard view.window?.isVisible == true, !view.isHidden, let renderer, root != nil else { return }
            if reduced && !needsStillFrame { return }
            guard inflight.wait(timeout: .now()) == .success else { return }
            guard let drawable = view.currentDrawable else {
                inflight.signal()
                return
            }
            let current = ProcessInfo.processInfo.systemUptime
            let delta = previousTime == 0 ? 1 / 30.0 : min(0.1, current - previousTime)
            previousTime = current
            needsStillFrame = false
            do {
                let output = try RealityRenderer.CameraOutput(
                    .singleProjection(colorTexture: drawable.texture))
                let ticket = DrawableTicket(drawable, semaphore: inflight)
                try renderer.updateAndRender(
                    deltaTime: delta, cameraOutput: output, onComplete: { _ in ticket.present() })
            } catch {
                inflight.signal()
                onError?(error.localizedDescription)
                view.isPaused = true
            }
        }
    }
}
