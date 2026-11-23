import XCTest

/// Bildschirmfotos für Pull Requests (Minze & Honig 2.0).
///
/// Läuft im Workflow „Bildschirmfotos“; hell/dunkel und Schriftgröße stellt der
/// Workflow am Simulator ein und reicht den Namen der Variante als
/// `MH_VARIANTE` durch (`TEST_RUNNER_MH_VARIANTE`). Die App startet mit
/// `-MhBildschirmfotos 1` im lokalen Modus mit erfundenen Testdaten
/// (`Bildschirmfotodaten`, nur Debug-Builds).
final class ScreenshotTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testAnsichten() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-MhBildschirmfotos", "1"]
        app.launch()
        _ = app.buttons["Anna"].firstMatch.waitForExistence(timeout: 15)

        foto(app, "01-heute")
        app.swipeUp()
        foto(app, "02-heute-mitte")
        app.swipeUp()
        foto(app, "03-heute-ende")

        nachOben(app)
        tippe(app.buttons["Statistik"].firstMatch)
        foto(app, "04-statistik")
        app.swipeUp()
        foto(app, "05-statistik-weiter")

        nachOben(app)
        tippe(app.buttons["Einstellungen"].firstMatch)
        foto(app, "06-einstellungen")
        app.swipeUp()
        foto(app, "07-einstellungen-weiter")

        zurueck(app)
        tippe(app.buttons["Nutzer verwalten"].firstMatch)
        foto(app, "08-nutzer")
    }

    @MainActor
    private func zurueck(_ app: XCUIApplication) {
        let knopf = app.navigationBars.buttons.firstMatch
        if knopf.waitForExistence(timeout: 3) {
            knopf.tap()
        }
        sleep(1)
    }

    @MainActor
    private func nachOben(_ app: XCUIApplication) {
        app.swipeDown()
        app.swipeDown()
        sleep(1)
    }

    @MainActor
    private func tippe(_ element: XCUIElement) {
        if element.waitForExistence(timeout: 5) {
            element.tap()
        }
    }

    @MainActor
    private func foto(_ app: XCUIApplication, _ name: String) {
        sleep(2)
        let variante = ProcessInfo.processInfo.environment["MH_VARIANTE"] ?? "standard"
        let anhang = XCTAttachment(screenshot: app.screenshot())
        anhang.name = "\(variante)-\(name)"
        anhang.lifetime = .keepAlways
        add(anhang)
    }
}
