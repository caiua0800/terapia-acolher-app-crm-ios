import XCTest

/// Login "utilitário": autentica o usuário demo e para no dashboard,
/// deixando a sessão salva no Keychain do simulador. Útil pra abrir o
/// app já logado sem navegar o smoke completo.
final class LoginOnlyUITests: XCTestCase {
    let email = "acolher@gmail.com"
    let password = "Acolher@2026"

    /// Digitação resiliente: garante o foco (teclado) antes de digitar e
    /// confere que o campo recebeu texto — o simulador do iOS 26 às vezes
    /// ignora o primeiro tap em secure fields.
    func type(_ text: String, into field: XCUIElement) {
        for attempt in 1...3 {
            field.tap()
            let focused = (field.value(forKey: "hasKeyboardFocus") as? Bool) ?? true
            if !focused {
                Thread.sleep(forTimeInterval: 0.5)
                continue
            }
            field.typeText(text)
            let value = field.value as? String ?? ""
            if !value.isEmpty && value != "E-mail" { return }
            Thread.sleep(forTimeInterval: 0.5)
            if attempt == 3 { XCTFail("Campo não recebeu texto após 3 tentativas") }
        }
    }

    func shoot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLoginOnly() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-session"]
        app.launch()

        let emailField = app.textFields.firstMatch
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Tela de login não apareceu")
        type(email, into: emailField)
        shoot(app, "01-email-digitado")
        let passwordField = app.secureTextFields.firstMatch
        type(password, into: passwordField)
        shoot(app, "02-senha-digitada")
        app.buttons["Entrar"].firstMatch.tap()

        let greeting = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Olá'")
        ).firstMatch
        let ok = greeting.waitForExistence(timeout: 30)
        shoot(app, "03-resultado")
        XCTAssertTrue(ok, "Dashboard não carregou após login")
    }
}
