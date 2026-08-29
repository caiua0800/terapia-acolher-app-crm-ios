import XCTest

/// Smoke de UI contra a API LOCAL (localhost:3000) com o usuário demo.
/// Valida o fluxo real: login → dashboard → menu → seções principais.
/// Screenshots anexadas em cada etapa (exportadas do .xcresult).
final class SmokeUITests: XCTestCase {
    let email = "acolher@gmail.com"
    let password = "Acolher@2026"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func shoot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFullSmoke() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-session"]
        app.launch()

        // ── Login
        let emailField = app.textFields.firstMatch
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Tela de login não apareceu")
        shoot(app, "01-login")
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields.firstMatch
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["Entrar"].firstMatch.tap()

        // ── Dashboard
        let greeting = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Olá'")
        ).firstMatch
        XCTAssertTrue(greeting.waitForExistence(timeout: 15), "Dashboard não carregou após login")
        shoot(app, "02-dashboard")

        // ── Navegação pelo menu
        func openSection(_ title: String, expect: String? = nil, shot: String) {
            let menu = app.buttons["menuButton"]
            XCTAssertTrue(menu.waitForExistence(timeout: 10), "Botão do menu sumiu")
            menu.tap()
            let item = app.buttons[title].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5), "Item \(title) não está no menu")
            shoot(app, "\(shot)-menu")
            item.tap()
            if let expect {
                let probe = app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS[cd] %@", expect)
                ).firstMatch
                _ = probe.waitForExistence(timeout: 12)
            } else {
                sleep(3)
            }
            shoot(app, shot)
        }

        openSection("Agenda", shot: "03-agenda")
        openSection("Pacientes", shot: "04-pacientes")
        openSection("Financeiro", shot: "05-financeiro")
        // Documentos e Anexos saíram do menu em 2026-08-30 — agora se acessam
        // pela ficha do paciente (ver DesignAuditUITests, que entra por lá).
        openSection("Configurações", shot: "08-configuracoes")

        // ── Notificações (sino) — tela empurrada; voltar antes de seguir
        let bell = app.buttons["bellButton"]
        if bell.waitForExistence(timeout: 5) {
            bell.tap()
            sleep(2)
            shoot(app, "09-notificacoes")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        // ── Volta pro início
        openSection("Início", shot: "10-inicio-final")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Olá'"))
                .firstMatch.waitForExistence(timeout: 10),
            "Não voltou pro dashboard"
        )
    }
}
