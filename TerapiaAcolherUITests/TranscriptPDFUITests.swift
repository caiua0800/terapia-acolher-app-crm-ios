import XCTest

/// Resumo e PDF na lista de transcrições, contra o backend LOCAL (nunca produção)
/// em http://localhost:3010 — usuário `teste@local.dev`, paciente Mariana Costa,
/// que tem uma transcrição com resumo pronto. Sem chave do Gemini no local,
/// "Gerar resumo" fica escondido (é a regra).
///
/// Fora da suíte padrão (`skippedTests` no `project.yml`); rodar com
///   xcodebuild test -only-testing:TerapiaAcolherUITests/TranscriptPDFUITests
final class TranscriptPDFUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws { continueAfterFailure = false }

    private func shoot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testVerResumoEBaixarPDFs() throws {
        app = XCUIApplication()
        app.launchArguments = ["--reset-session", "--api-base-url", "http://localhost:3010"]
        app.launch()

        let email = app.textFields.firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 20))
        email.tap(); email.typeText("teste@local.dev")
        let senha = app.secureTextFields.firstMatch
        senha.tap(); senha.typeText("senha-local-123")
        app.buttons["Entrar"].firstMatch.tap()
        let ola = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Olá'")).firstMatch
        XCTAssertTrue(ola.waitForExistence(timeout: 40), "dashboard não carregou")
        for rotulo in ["Agora Não", "Deixar para depois"] where app.buttons[rotulo].waitForExistence(timeout: 3) {
            app.buttons[rotulo].tap()
        }

        let menu = app.buttons["menuButton"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        app.buttons["Transcrições"].firstMatch.tap()
        let paciente = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Mariana'")).firstMatch
        XCTAssertTrue(paciente.waitForExistence(timeout: 20), "paciente não apareceu")
        paciente.tap()

        let verResumo = app.buttons["Ver resumo"].firstMatch
        XCTAssertTrue(verResumo.waitForExistence(timeout: 20), "botão Ver resumo não apareceu")
        XCTAssertTrue(app.buttons["Baixar em PDF"].firstMatch.exists, "menu de PDF não apareceu")
        XCTAssertFalse(app.buttons["Gerar resumo"].exists, "sem IA local, Gerar resumo não pode aparecer")
        shoot("01-lista")

        // Ver resumo → folha com o conteúdo e o botão de PDF.
        verResumo.tap()
        XCTAssertTrue(app.staticTexts["SENTIMENTOS"].waitForExistence(timeout: 15), "resumo não abriu")
        shoot("02-resumo")
        let baixarResumo = app.buttons["Baixar resumo em PDF"].firstMatch
        XCTAssertTrue(baixarResumo.waitForExistence(timeout: 5))
        baixarResumo.tap()
        XCTAssertTrue(app.otherElements["QLPreviewControllerView"].waitForExistence(timeout: 20)
                      || app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS 'resumo-'")).firstMatch.waitForExistence(timeout: 5),
                      "Quick Look do resumo não abriu")
        sleep(2)
        shoot("03-pdf-resumo")
        app.navigationBars.buttons["OK"].firstMatch.tap()
        sleep(1)
        app.buttons["Fechar"].firstMatch.tap()

        // Menu do cartão → Transcrição em PDF.
        let menuPdf = app.buttons["Baixar em PDF"].firstMatch
        XCTAssertTrue(menuPdf.waitForExistence(timeout: 10))
        menuPdf.tap()
        let item = app.buttons["Transcrição em PDF"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "item do menu não apareceu")
        item.tap()
        XCTAssertTrue(app.otherElements["QLPreviewControllerView"].waitForExistence(timeout: 20)
                      || app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS 'transcricao-'")).firstMatch.waitForExistence(timeout: 5),
                      "Quick Look da transcrição não abriu")
        sleep(2)
        shoot("04-pdf-transcricao")
    }
}
