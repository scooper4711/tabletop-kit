import Foundation
import Testing
@testable import TablesideSync

/// A device's shared library moving between CloudKit's environments (R6.3).
struct SyncEnvironmentTests {
    private let engineState = Data("position in one environment".utf8)

    @Test func readsTheEnvironmentABuildNames() {
        #expect(SyncEnvironment.named("Development") == .development)
        #expect(SyncEnvironment.named("Production") == .production)
    }

    @Test func aBuildNamingNoKnownEnvironmentIsProduction() {
        #expect(SyncEnvironment.named(nil) == .production)
        #expect(SyncEnvironment.named("") == .production)
        #expect(SyncEnvironment.named("Staging") == .production)
    }

    @Test func productionKeepsThePlainAccountNameThatReleasedAppsRead() {
        #expect(SyncEnvironment.production.accountName(of: "_user") == "_user")
    }

    @Test func developmentNamesTheAccountApart() {
        #expect(SyncEnvironment.development.accountName(of: "_user") == "Development:_user")
    }

    @Test func movingToDevelopmentForgetsProductionsPosition() async throws {
        let device = try await SyncingDevice()
        await engine(of: device, in: .production).accountKnown("_user")
        await device.sync.save(engineState)

        await engine(of: device, in: .development).accountKnown("_user")

        #expect(await device.sync.load() == nil)
    }

    @Test func movingBackToProductionForgetsDevelopmentsPosition() async throws {
        let device = try await SyncingDevice()
        await engine(of: device, in: .development).accountKnown("_user")
        await device.sync.save(engineState)

        await engine(of: device, in: .production).accountKnown("_user")

        #expect(await device.sync.load() == nil)
    }

    @Test func stayingInAnEnvironmentKeepsItsPosition() async throws {
        let device = try await SyncingDevice()
        let development = engine(of: device, in: .development)
        await development.accountKnown("_user")
        await device.sync.save(engineState)

        await development.accountKnown("_user")

        #expect(await device.sync.load() == engineState)
    }

    @Test func aSignInReportsTheAccountInTheEnginesEnvironment() async {
        let handler = FakeHandler(zone: "Campaigns")
        let engine = SyncEngine(handlers: [handler], store: MemoryStateStore(), environment: .development)

        await engine.accountChanged(.signIn(currentUser: .init(recordName: "_user")))

        #expect(await handler.accounts == ["Development:_user"])
    }

    private func engine(of device: SyncingDevice, in environment: SyncEnvironment) -> SyncEngine {
        SyncEngine(handlers: [device.sync], store: device.sync, environment: environment)
    }
}
