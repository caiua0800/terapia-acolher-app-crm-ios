import XCTest

/// Compra de créditos dentro do app, contra o backend LOCAL (nunca produção):
/// CRM em http://localhost:3010 → sistema de leads local → Asaas sandbox.
///
/// Roteiro: Créditos → pacote → Pix (gera QR, cancela) → cartão novo 3x
/// salvando → cartão salvo (senha errada, depois certa) → remove o cartão.
/// Usuário `ios@local.dev`, já conectado ao terapeuta de teste 9102 do leads
/// local (o saldo não sobe com SHADOW_MODE=true lá — é proposital).
///
/// Fora da suíte padrão (`skippedTests` no `project.yml`): comente a linha,
/// rode `xcodegen generate` e depois:
///   xcodebuild test -only-testing:TerapiaAcolherUITests/LeadsCheckoutUITests
final class LeadsCheckoutUITests: XCTestCase {
    let email = "ios@local.dev"
    let password = "senha-ios-123"
    let apiBaseURL = "http://localhost:3010"

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shoot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func fecharAvisoDoSistema() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for rotulo in ["Deixar para depois", "Agora Não", "Agora não", "Not Now", "Não Salvar", "Permitir", "Allow"] {
            for alvo in [app, springboard] {
                guard let alvo else { continue }
                let botao = alvo.buttons[rotulo]
                if botao.exists, botao.isHittable {
                    botao.tap()
                    sleep(1)
                    return
                }
            }
        }
    }

    private func login() {
        app = XCUIApplication()
        app.launchArguments = ["--reset-session", "--api-base-url", apiBaseURL]
        app.launch()

        let emailField = app.textFields.firstMatch
        XCTAssertTrue(emailField.waitForExistence(timeout: 20), "tela de login não apareceu")
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields.firstMatch
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["Entrar"].firstMatch.tap()

        let greeting = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Olá'")).firstMatch
        XCTAssertTrue(greeting.waitForExistence(timeout: 40), "dashboard não carregou")
        _ = app.buttons["Agora Não"].waitForExistence(timeout: 6)
        fecharAvisoDoSistema()
        if app.buttons["Deixar para depois"].waitForExistence(timeout: 4) {
            app.buttons["Deixar para depois"].tap()
            sleep(1)
        }
    }

    /// Entra pelo cartão de saldo do Início (o atalho que a terapeuta usa).
    private func abrirCreditos() {
        let atalho = app.buttons.matching(NSPredicate(format: "label CONTAINS 'créditos restantes' OR label CONTAINS 'crédito restante'")).firstMatch
        XCTAssertTrue(atalho.waitForExistence(timeout: 30), "cartão de saldo não apareceu no Início")
        atalho.tap()
        XCTAssertTrue(app.staticTexts["SEU SALDO"].waitForExistence(timeout: 25), "Créditos não carregou")
    }

    private func abrirPrimeiroPacote() {
        let pacote = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Comprar'")).firstMatch
        XCTAssertTrue(pacote.waitForExistence(timeout: 15), "pacote não apareceu")
        pacote.tap()
        XCTAssertTrue(app.staticTexts["VOCÊ ESTÁ COMPRANDO"].waitForExistence(timeout: 25), "checkout não abriu")
        // O botão só acende com a cotação.
        let pagar = app.buttons["payButton"]
        let pronto = NSPredicate(format: "isEnabled == true")
        expectation(for: pronto, evaluatedWith: pagar)
        waitForExpectations(timeout: 20)
    }

    private func voltar() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)
    }

    private func digitar(_ id: String, _ texto: String) {
        let campo = app.textFields[id]
        XCTAssertTrue(campo.waitForExistence(timeout: 5), "campo \(id) não apareceu")
        var tentativas = 0
        while !campo.isHittable, tentativas < 4 {
            app.swipeUp()
            tentativas += 1
        }
        campo.tap()
        campo.typeText(texto)
    }

    private func esperarTexto(_ trecho: String, _ timeout: TimeInterval = 60) -> Bool {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", trecho)).firstMatch
            .waitForExistence(timeout: timeout)
    }

    func testCompraDentroDoApp() throws {
        login()
        abrirCreditos()
        shoot("01-creditos")

        // ── Pix: gera, mostra o QR e cancela ──
        abrirPrimeiroPacote()
        shoot("02-checkout-pix")
        app.buttons["payButton"].tap()
        XCTAssertTrue(app.staticTexts["PAGUE COM PIX"].waitForExistence(timeout: 60), "tela do Pix não apareceu")
        XCTAssertTrue(app.images["QR code do Pix"].waitForExistence(timeout: 10), "QR do Pix não apareceu")
        XCTAssertTrue(esperarTexto("Aguardando o pagamento", 5))
        shoot("03-pix")
        let cancelar = app.buttons.matching(NSPredicate(format: "label == 'Cancelar pedido'")).firstMatch
        if !cancelar.isHittable { app.swipeUp() }
        cancelar.tap()
        let confirmar = app.buttons.matching(NSPredicate(format: "label == 'Cancelar pedido'")).element(boundBy: 1)
        XCTAssertTrue(confirmar.waitForExistence(timeout: 5), "confirmação do cancelamento não apareceu")
        confirmar.tap()
        XCTAssertTrue(esperarTexto("não está mais valendo", 30), "pedido não ficou cancelado")
        shoot("04-pix-cancelado")
        voltar()

        // ── Cartão novo, 3x, salvando ──
        abrirPrimeiroPacote()
        app.buttons["Cartão"].firstMatch.tap()
        let outro = app.buttons["Usar outro cartão"]
        if outro.exists { outro.tap() }
        digitar("cardNumber", "4111111111111112")
        app.buttons["payButton"].tap()
        XCTAssertTrue(esperarTexto("Número do cartão inválido", 5), "validação do número não apareceu")
        let numero = app.textFields["cardNumber"]
        numero.tap()
        numero.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 22) + "5162306219378829")
        XCTAssertFalse(esperarTexto("Número do cartão inválido", 1), "erro do número não sumiu ao corrigir")
        digitar("cardHolder", "MARIA TESTE")
        digitar("cardExpiry", "0530")
        digitar("cardCvv", "318")
        digitar("cardCep", "01001000")
        digitar("cardAddressNumber", "100")
        app.buttons["Parcelas"].tap()
        let tres = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '3x de'")).firstMatch
        XCTAssertTrue(tres.waitForExistence(timeout: 5), "opção 3x não apareceu")
        tres.tap()
        let salvar = app.buttons["saveCardToggle"]
        var t = 0
        while !salvar.isHittable, t < 4 { app.swipeUp(); t += 1 }
        salvar.tap()
        shoot("05-cartao")
        app.buttons["payButton"].tap()
        XCTAssertTrue(esperarTexto("Pagamento confirmado", 90), "cartão não foi aprovado")
        XCTAssertTrue(esperarTexto("final 8829 · 3x", 5), "detalhe do cartão 3x não apareceu")
        shoot("06-pago")
        voltar()

        // ── Cartão salvo: senha errada, depois certa ──
        XCTAssertTrue(app.staticTexts["CARTÕES SALVOS"].waitForExistence(timeout: 20), "cartão salvo não apareceu em Créditos")
        shoot("07-creditos-com-cartao")
        app.swipeDown()
        abrirPrimeiroPacote()
        app.buttons["Cartão"].firstMatch.tap()
        let salvo = app.buttons["Mastercard final 8829"]
        XCTAssertTrue(salvo.waitForExistence(timeout: 5), "cartão salvo não aparece no checkout")
        XCTAssertTrue(salvo.isSelected, "cartão salvo não veio escolhido")
        app.buttons["payButton"].tap()
        let senha = app.secureTextFields["stepUpPassword"]
        XCTAssertTrue(senha.waitForExistence(timeout: 10), "pedido de senha não apareceu")
        senha.tap()
        senha.typeText("senha-errada")
        app.buttons["stepUpConfirm"].tap()
        XCTAssertTrue(esperarTexto("Senha incorreta", 15), "senha errada não avisou")
        shoot("08-senha-errada")
        senha.tap()
        senha.typeText(password)
        app.buttons["stepUpConfirm"].tap()
        XCTAssertTrue(esperarTexto("Pagamento confirmado", 90), "compra com cartão salvo não foi aprovada")
        shoot("09-pago-cartao-salvo")
        voltar()

        // ── Remove o cartão (deixa o próximo teste começar do zero) ──
        let remover = app.buttons["Remover Mastercard final 8829"]
        var r = 0
        while !remover.isHittable, r < 5 { app.swipeUp(); r += 1 }
        remover.tap()
        let confirmarRemocao = app.buttons["Remover"]
        XCTAssertTrue(confirmarRemocao.waitForExistence(timeout: 5))
        confirmarRemocao.tap()
        let sumiu = NSPredicate(format: "exists == false")
        expectation(for: sumiu, evaluatedWith: app.staticTexts["CARTÕES SALVOS"])
        waitForExpectations(timeout: 20)
        shoot("10-cartao-removido")
    }
}
