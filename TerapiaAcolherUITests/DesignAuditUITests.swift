import XCTest

/// Varredura visual de todas as telas para auditoria de design.
/// Não é teste de regressão: navega e fotografa, tolerante a falha em cada etapa.
/// Rodar: xcodebuild test -only-testing:TerapiaAcolherUITests/DesignAuditUITests
final class DesignAuditUITests: XCTestCase {
    let email = "acolher@gmail.com"
    let password = "Acolher@2026"

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

    private func login() {
        app = XCUIApplication()
        app.launchArguments = ["--reset-session"]
        app.launch()

        let emailField = app.textFields.firstMatch
        XCTAssertTrue(emailField.waitForExistence(timeout: 15), "login não apareceu")
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields.firstMatch
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["Entrar"].firstMatch.tap()

        let greeting = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Olá'")).firstMatch
        XCTAssertTrue(greeting.waitForExistence(timeout: 25), "dashboard não carregou")
    }

    private func openSection(_ title: String) {
        let menu = app.buttons["menuButton"]
        guard menu.waitForExistence(timeout: 8) else { return }
        menu.tap()
        let item = app.buttons[title].firstMatch
        guard item.waitForExistence(timeout: 5) else { return }
        item.tap()
        sleep(4)
    }

    /// Volta pra raiz da NavigationStack (várias vezes se estiver fundo).
    private func popToRoot(times: Int = 1) {
        for _ in 0 ..< times {
            let back = app.navigationBars.buttons.firstMatch
            if back.exists, back.isHittable { back.tap(); sleep(1) }
        }
    }

    private func tapText(_ label: String, timeout: TimeInterval = 5) -> Bool {
        let element = app.staticTexts[label].firstMatch
        guard element.waitForExistence(timeout: timeout) else { return false }
        element.tap()
        sleep(3)
        return true
    }

    private func tapButton(_ label: String, timeout: TimeInterval = 5) -> Bool {
        let element = app.buttons[label].firstMatch
        guard element.waitForExistence(timeout: timeout) else { return false }
        element.tap()
        sleep(3)
        return true
    }

    // MARK: - Varredura

    func testCaptureAllScreens() throws {
        login()
        shoot("01-inicio")

        // Início → Ver tudo (próximas sessões)
        if tapText("Ver tudo") { shoot("02-inicio-ver-tudo"); popToRoot() }

        // Notificações (sino)
        if tapButton("bellButton") { shoot("03-notificacoes"); popToRoot() }

        // ── Agenda: lista / semana / mês
        openSection("Agenda")
        shoot("04-agenda-lista")
        if tapButton("Semana") { shoot("05-agenda-semana") }
        if tapButton("Mês") { shoot("06-agenda-mes") }
        if tapButton("Lista") { sleep(1) }

        // Detalhe de sessão (primeiro card da lista)
        let firstCard = app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] ':'")).firstMatch
        if firstCard.waitForExistence(timeout: 5) {
            firstCard.tap()
            sleep(4)
            shoot("07-agenda-detalhe-sessao")
            popToRoot()
        }

        // Nova sessão (FAB)
        let fabs = app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] 'plus' OR label CONTAINS[cd] 'add'"))
        if fabs.firstMatch.waitForExistence(timeout: 4) {
            fabs.firstMatch.tap()
            sleep(3)
            shoot("08-agenda-nova-sessao")
            _ = tapButton("Cancelar")
        }

        // ── Pacientes
        openSection("Pacientes")
        shoot("09-pacientes-lista")
        let firstPatient = app.buttons.element(boundBy: 3)
        if firstPatient.exists, firstPatient.isHittable {
            firstPatient.tap()
            sleep(4)
            shoot("10-paciente-detalhe")
            for aba in ["Financeiro", "Sessões", "Arquivos", "Anotações"] {
                if tapButton(aba, timeout: 3) { shoot("11-paciente-aba-\(aba.lowercased())") }
            }
            popToRoot(times: 2)
        }

        // ── Prontuários / Anamneses
        openSection("Prontuários")
        shoot("12-prontuarios")
        if tapButton("Modelos", timeout: 4) { shoot("13-prontuarios-modelos") }

        openSection("Anamneses")
        shoot("14-anamneses")

        // ── Financeiro
        openSection("Financeiro")
        shoot("15-financeiro-home")
        if tapText("Cobranças", timeout: 4) { shoot("16-financeiro-cobrancas"); popToRoot() }
        if tapText("Carteira", timeout: 4) { shoot("17-financeiro-carteira"); popToRoot() }

        // Documentos e Anexos não estão mais no menu: a varredura deles acontece
        // na ficha do paciente, junto com prontuário e anotações.

        // ── Configurações + subtelas
        openSection("Configurações")
        shoot("20-configuracoes")
        for (index, item) in ["Perfil profissional", "Consultório", "Grupos de pacientes",
                              "Modelos de documento", "Preferências da agenda",
                              "Google Agenda", "Alterar senha"].enumerated() {
            if tapText(item, timeout: 4) {
                shoot("21-\(index)-config-\(item.prefix(12).replacingOccurrences(of: " ", with: "-"))")
                popToRoot()
            }
        }
    }
}
