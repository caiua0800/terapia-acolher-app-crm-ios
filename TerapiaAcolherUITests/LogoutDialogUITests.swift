import XCTest

/// Verificação pontual: o diálogo de confirmação de "Sair" em Configurações
/// deve aparecer ancorado no botão (parte de baixo), não solto no topo da tela.
final class LogoutDialogUITests: XCTestCase {
    let email = "acolher@gmail.com"
    let password = "Acolher@2026"

    func shoot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLogoutDialogAnchoredToButton() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--reset-session"]
        app.launch()

        let emailField = app.textFields.firstMatch
        XCTAssertTrue(emailField.waitForExistence(timeout: 10))
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields.firstMatch
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["Entrar"].firstMatch.tap()

        let greeting = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Olá'")
        ).firstMatch
        XCTAssertTrue(greeting.waitForExistence(timeout: 15))

        let menu = app.buttons["menuButton"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        sleep(2)
        let item = app.buttons["Configurações"].firstMatch
        var found = false
        for _ in 0..<3 {
            menu.tap()
            found = item.waitForExistence(timeout: 5)
            if found { break }
        }
        shoot(app, "menu-aberto")
        XCTAssertTrue(found, "Item Configurações não apareceu no menu")
        item.tap()

        let sair = app.buttons["Sair"].firstMatch
        XCTAssertTrue(sair.waitForExistence(timeout: 10))
        app.swipeUp()
        sair.tap()

        let dialogTitle = app.staticTexts["Sair da conta?"]
        XCTAssertTrue(dialogTitle.waitForExistence(timeout: 5), "Diálogo não apareceu")
        shoot(app, "logout-dialog")

        // Ancorado embaixo: o título do diálogo deve estar na metade inferior da tela.
        let screenHeight = app.frame.height
        XCTAssertGreaterThan(
            dialogTitle.frame.midY, screenHeight * 0.5,
            "Diálogo apareceu na metade de cima da tela (não ancorado no botão Sair)"
        )

        // iOS 26: o diálogo ancorado fecha tocando fora (Cancelar não vira botão acessível).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
    }
}
