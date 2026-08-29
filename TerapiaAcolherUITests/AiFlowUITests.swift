import XCTest

/// Deixa o app logado (token no Keychain) e navega até o formulário de
/// prontuário para conferir que o card da IA aparece.
/// Rodar contra o backend LOCAL: xcodebuild test -only-testing:TerapiaAcolherUITests/AiFlowUITests
final class AiFlowUITests: XCTestCase {
    let email = "teste@local.dev"
    let password = "Teste@2026"

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shoot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testReachAiComposer() throws {
        app = XCUIApplication()
        app.launchArguments = ["--reset-session"]
        app.launch()

        // ── Login
        let emailField = app.textFields.firstMatch
        XCTAssertTrue(emailField.waitForExistence(timeout: 15), "login não apareceu")
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields.firstMatch
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["Entrar"].firstMatch.tap()

        let greeting = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Olá'")
        ).firstMatch
        XCTAssertTrue(greeting.waitForExistence(timeout: 25), "dashboard não carregou")
        shoot("01-dashboard")

        // ── Menu → Prontuários
        let menu = app.buttons["menuButton"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        sleep(2) // deixa a animação do drawer terminar antes de procurar o item

        var item = app.buttons["Prontuários"].firstMatch
        if !item.waitForExistence(timeout: 6) {
            // drawer não abriu no primeiro toque — tenta de novo
            shoot("02a-drawer-nao-abriu")
            menu.tap()
            sleep(2)
            item = app.buttons["Prontuários"].firstMatch
        }
        XCTAssertTrue(item.waitForExistence(timeout: 8), "item Prontuários não apareceu no menu")
        item.tap()
        sleep(3)
        shoot("02-prontuarios")

        // ── Paciente
        let patient = app.staticTexts["Mariana Costa"].firstMatch
        XCTAssertTrue(patient.waitForExistence(timeout: 10), "paciente não listado")
        patient.tap()
        sleep(3)
        shoot("03-timeline")

        // ── Novo registro (FAB) → escolher modelo
        let fab = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[cd] 'plus' OR label CONTAINS[cd] 'add'")
        ).firstMatch
        if fab.waitForExistence(timeout: 6) {
            fab.tap()
            sleep(2)
            shoot("04-escolher-modelo")
        }

        // Modelo "Padrão"
        let template = app.staticTexts["Padrão"].firstMatch
        if template.waitForExistence(timeout: 6) {
            template.tap()
            sleep(3)
        }
        shoot("05-formulario-com-ia")

        // A prova: o card da IA está na tela
        let aiCard = app.staticTexts["Escrever solto e organizar"].firstMatch
        XCTAssertTrue(
            aiCard.waitForExistence(timeout: 8),
            "card da IA não apareceu — /ai/status deve estar respondendo enabled=false"
        )

        // Abre o compositor pra deixar pronto pro teste manual
        aiCard.tap()
        sleep(2)
        shoot("06-compositor-aberto")
    }
}
