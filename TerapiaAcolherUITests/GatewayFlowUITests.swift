import XCTest

/// Fluxo do Gateway Acolher contra o backend LOCAL (nunca produção).
///
/// Rodar (backend em http://localhost:3010, usuário de teste já criado):
///   xcodebuild test -only-testing:TerapiaAcolherUITests/GatewayFlowUITests/test01AbrirConta
///   (aprovar a conta pela API admin)
///   xcodebuild test -only-testing:TerapiaAcolherUITests/GatewayFlowUITests/test02ContaAprovada
///
/// Fora da suíte padrão (`skippedTests` no `project.yml`): depende do backend
/// local e de fotos na galeria do simulador
/// (`xcrun simctl addmedia <udid> foto1.png foto2.png foto3.png`).
/// Atenção: `-only-testing:` NÃO desfaz o `skippedTests` do esquema — para
/// rodar, comente a linha `- GatewayFlowUITests` no `project.yml` e rode
/// `xcodegen generate` antes.
final class GatewayFlowUITests: XCTestCase {
    let email = "terapeuta.ios@teste.local"
    let password = "Teste@2026"
    let apiBaseURL = "http://localhost:3010"

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    // MARK: Utilitários

    private func shoot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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

        let greeting = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Olá'")
        ).firstMatch
        XCTAssertTrue(greeting.waitForExistence(timeout: 40), "dashboard não carregou")
        _ = app.buttons["Agora Não"].waitForExistence(timeout: 8)
        fecharAvisoDoSistema()
    }

    /// O iOS oferece "Salvar senha?" depois do login e o alerta do sistema
    /// cobre a tela inteira — sem fechar, nada mais é tocável.
    private func fecharAvisoDoSistema() {
        // O diálogo do chaveiro vem de outro processo, mas aparece dentro da
        // árvore do app (remote view) — dá pra tocar por aqui mesmo.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for rotulo in ["Agora Não", "Agora não", "Not Now", "Não Salvar"] {
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

    private func openSection(_ title: String) {
        let menu = app.buttons["menuButton"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15), "menu não apareceu")
        for _ in 1 ... 4 {
            // Um alerta do sistema pode ter engolido o toque anterior.
            fecharAvisoDoSistema()
            if menu.isHittable { menu.tap() }
            let item = app.buttons[title].firstMatch
            if item.waitForExistence(timeout: 5) {
                item.tap()
                sleep(3)
                return
            }
        }
        XCTFail("seção \(title) não apareceu")
    }

    @discardableResult
    private func tapButton(_ label: String, timeout: TimeInterval = 10) -> Bool {
        let element = app.buttons[label].firstMatch
        guard element.waitForExistence(timeout: timeout) else { return false }
        var tentativas = 0
        while !element.isHittable, tentativas < 4 {
            app.swipeUp()
            tentativas += 1
        }
        element.tap()
        return true
    }

    /// Preenche o campo limpando o que já estiver lá (o assistente reabre com
    /// os dados salvos, então digitar por cima concatenaria).
    private func preencher(_ identifier: String, _ texto: String, placeholder: String) {
        let campo = app.textFields[identifier]
        XCTAssertTrue(campo.waitForExistence(timeout: 10), "campo \(identifier) não apareceu")
        var tentativas = 0
        while !campo.isHittable, tentativas < 5 {
            app.swipeUp()
            tentativas += 1
        }
        campo.tap()
        if let valor = campo.value as? String, !valor.isEmpty, valor != placeholder {
            campo.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: valor.count))
        }
        campo.typeText(texto)
    }

    /// O formatador pt-BR usa espaço fixo (U+00A0) entre "R$" e o número;
    /// comparar com espaço comum falha por um caractere invisível.
    private func dinheiro(_ elemento: XCUIElement) -> String {
        elemento.label
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    private func abrirGateway() {
        openSection("Fluxo de caixa")
        XCTAssertTrue(tapButton("Gateway Acolher"), "atalho do Gateway não apareceu")
        sleep(4)
    }

    /// Escolhe a primeira foto da galeria do simulador para um documento.
    private func enviarDocumentoDaGaleria(_ tipo: String) {
        let botao = app.buttons["gwEnviar-\(tipo)"]
        XCTAssertTrue(botao.waitForExistence(timeout: 15), "botão de \(tipo) não apareceu")
        if botao.label.contains("Enviar de novo") { return } // já enviado

        var abriuGaleria = false
        for tentativa in 1 ... 4 {
            tocar(botao)
            if app.buttons["Escolher da galeria"].waitForExistence(timeout: 8) {
                app.buttons["Escolher da galeria"].tap()
                abriuGaleria = true
                break
            }
            if tentativa == 4 {
                XCTFail("opção de galeria não apareceu para \(tipo)")
            }
            sleep(3)
        }
        guard abriuGaleria else { return }

        // PHPicker roda fora do processo do app: as células da grade nunca são
        // "hittable" para o XCTest, então o toque vai por coordenada.
        let foto = app.images.matching(
            NSPredicate(format: "identifier == 'PXGGridLayout-Info'")
        ).firstMatch
        XCTAssertTrue(foto.waitForExistence(timeout: 25), "galeria sem fotos")
        sleep(2)
        foto.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // Espera determinística: o botão vira "Enviar de novo" quando o
        // documento entra na conta.
        let prazo = Date().addingTimeInterval(60)
        while Date() < prazo, !botao.label.contains("Enviar de novo") {
            sleep(1)
        }
        XCTAssertTrue(
            botao.label.contains("Enviar de novo"),
            "envio de \(tipo) não concluiu (rótulo: \(botao.label))"
        )
    }

    /// Toca esperando ficar tocável; cai no toque por coordenada quando o
    /// elemento existe mas o XCTest o considera coberto (grade do PHPicker,
    /// tela ainda fechando um sheet).
    private func tocar(_ elemento: XCUIElement) {
        var esperas = 0
        while !elemento.isHittable, esperas < 16 {
            sleep(1)
            esperas += 1
            // Pode estar abaixo da dobra (a lista de documentos é longa).
            if esperas % 4 == 0 { app.swipeUp() }
        }
        if elemento.isHittable {
            elemento.tap()
        } else {
            elemento.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    // MARK: 1 — abertura da conta

    func test01AbrirConta() throws {
        login()
        abrirGateway()
        shoot("01-gateway-apresentacao")

        // Conta nova mostra a apresentação; conta já começada, "Continuar
        // cadastro" — o teste roda nos dois casos.
        if !tapButton("Ativar recebimentos", timeout: 8) {
            XCTAssertTrue(
                tapButton("Continuar cadastro", timeout: 8),
                "nem apresentação nem cadastro em andamento apareceram"
            )
        }
        sleep(3)
        shoot("02-etapa1-tipo-de-conta")

        // Percorre as etapas preenchendo o que a tela pedir.
        for _ in 0 ..< 5 {
            if app.switches["gwAceite"].exists { break }

            if app.textFields["gwLegalName"].exists {
                preencher("gwLegalName", "Carlos Ios Teste", placeholder: "Como está no documento")
                preencher("gwCpfCnpj", "12345678909", placeholder: "000.000.000-00")
                preencher("gwBirthDate", "10051990", placeholder: "00/00/0000")
                preencher("gwPhone", "11988880002", placeholder: "+55 (11) 99999-9999")
                preencher("gwEmail", "terapeuta.ios@teste.local", placeholder: "voce@email.com")
                shoot("03-etapa2-dados")
            } else if app.textFields["gwCep"].exists {
                preencher("gwCep", "01310100", placeholder: "00000-000")
                preencher("gwStreet", "Av. Paulista", placeholder: "Av. Paulista")
                preencher("gwNumber", "1000", placeholder: "1000")
                preencher("gwDistrict", "Bela Vista", placeholder: "Bela Vista")
                preencher("gwCity", "Sao Paulo", placeholder: "São Paulo")
                preencher("gwState", "SP", placeholder: "SP")
                shoot("04-etapa3-endereco")
            } else if app.buttons["gwEnviar-IDENTITY_FRONT"].exists {
                shoot("05-etapa4-documentos")
                enviarDocumentoDaGaleria("IDENTITY_FRONT")
                enviarDocumentoDaGaleria("IDENTITY_BACK")
                enviarDocumentoDaGaleria("SELFIE")
                shoot("06-etapa4-documentos-enviados")
            }

            XCTAssertTrue(tapButton("Continuar"), "não deu pra avançar de etapa")
            sleep(4)
        }

        // Etapa 5 — termos
        let aceite = app.switches["gwAceite"].firstMatch
        XCTAssertTrue(aceite.waitForExistence(timeout: 10), "toggle de aceite não apareceu")
        var tentativas = 0
        while !aceite.isHittable, tentativas < 5 {
            app.swipeUp()
            tentativas += 1
        }
        if (aceite.value as? String) != "1" { aceite.tap() }
        shoot("07-etapa5-termos")
        XCTAssertTrue(tapButton("Enviar para análise"), "envio para análise")
        sleep(6)
        shoot("08-enviada-para-analise")
        XCTAssertTrue(tapButton("Fechar"), "confirmação de envio não apareceu")
        sleep(5)
        shoot("09-conta-em-analise")
        XCTAssertTrue(
            app.staticTexts["Conta em análise"].waitForExistence(timeout: 20),
            "tela de análise não apareceu"
        )
    }

    // MARK: 2 — conta aprovada: Pix, pagamento simulado e saque

    func test02ContaAprovada() throws {
        login()
        abrirGateway()
        shoot("10-conta-aprovada-saldo")

        let saldo = app.staticTexts["gwSaldo"]
        XCTAssertTrue(saldo.waitForExistence(timeout: 20), "cartão de saldo não apareceu")
        XCTAssertEqual(dinheiro(saldo), "R$ 1.000,00", "saldo inicial diferente do bônus de simulação")

        // Extrato
        XCTAssertTrue(tapButton("Extrato"), "botão de extrato")
        sleep(4)
        shoot("11-extrato")
        app.navigationBars.buttons.firstMatch.tap()
        sleep(2)

        // Chaves Pix (o rótulo do link junta título e subtítulo: usa o id)
        let chaves = app.buttons["gwChaves"]
        XCTAssertTrue(chaves.waitForExistence(timeout: 10), "atalho de chaves Pix")
        tocar(chaves)
        sleep(3)
        shoot("12-chaves-pix")
        app.navigationBars.buttons.firstMatch.tap()
        sleep(2)
    }

    // MARK: 3 — cobrança por Pix pelo gateway

    func test03CobrarPorPix() throws {
        login()
        openSection("Fluxo de caixa")
        XCTAssertTrue(tapButton("Cobranças"), "atalho de cobranças")
        sleep(3)

        // Primeiro paciente da lista
        let paciente = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Paciente Gateway'")
        ).firstMatch
        XCTAssertTrue(paciente.waitForExistence(timeout: 20), "paciente de teste não apareceu")
        paciente.tap()
        sleep(4)
        shoot("13-cobrancas-do-paciente")

        // Abre a cobrança e gera o Pix pelo gateway
        let cobranca = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Sessao de teste'")
        ).firstMatch
        XCTAssertTrue(cobranca.waitForExistence(timeout: 15), "cobrança de teste não apareceu")
        cobranca.tap()
        sleep(4)
        shoot("14-detalhe-da-cobranca")

        XCTAssertTrue(tapButton("Cobrar por Pix (Gateway Acolher)"), "ação de cobrar por Pix")
        sleep(6)
        shoot("15-pix-com-qrcode")

        XCTAssertTrue(tapButton("Simular pagamento (teste)"), "botão de simular pagamento")
        sleep(6)
        shoot("16-pagamento-confirmado")
        XCTAssertTrue(
            app.staticTexts["Pagamento confirmado"].waitForExistence(timeout: 20),
            "pagamento simulado não confirmou"
        )
        XCTAssertTrue(tapButton("Fechar"), "fechar sheet do Pix")
        sleep(3)
    }

    // MARK: 4 — saque

    func test04Saque() throws {
        login()
        abrirGateway()

        let saldo = app.staticTexts["gwSaldo"]
        XCTAssertTrue(saldo.waitForExistence(timeout: 20), "cartão de saldo não apareceu")
        shoot("17-saldo-apos-pagamento")
        XCTAssertEqual(dinheiro(saldo), "R$ 1.097,01", "saldo não bateu depois do Pix pago")

        XCTAssertTrue(tapButton("Sacar"), "botão de sacar")
        sleep(3)
        preencher("gwValorSaque", "200", placeholder: "0,00")
        preencher("gwChaveSaque", "12345678909", placeholder: "000.000.000-00")
        shoot("18-pedido-de-saque")
        XCTAssertTrue(tapButton("Pedir saque"), "botão pedir saque")
        sleep(2)
        XCTAssertTrue(tapButton("Pedir saque"), "confirmação do saque")
        sleep(6)
        shoot("19-saque-aguardando")
        XCTAssertTrue(tapButton("OK"), "aviso de saque pedido")
        sleep(3)
        XCTAssertTrue(
            app.staticTexts["AGUARDANDO APROVAÇÃO"].waitForExistence(timeout: 20),
            "saque não ficou aguardando aprovação"
        )
        shoot("20-lista-de-saques")

        // Cancela o saque: o valor volta na hora
        XCTAssertTrue(tapButton("Cancelar"), "botão cancelar saque")
        sleep(2)
        XCTAssertTrue(tapButton("Cancelar saque"), "confirmação do cancelamento")
        sleep(6)
        shoot("21-saque-cancelado")
        XCTAssertTrue(
            app.staticTexts["CANCELADO"].waitForExistence(timeout: 20),
            "saque não ficou cancelado"
        )
    }
}
