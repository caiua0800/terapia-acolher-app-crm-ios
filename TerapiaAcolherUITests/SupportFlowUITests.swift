import XCTest

/// Suporte (chat com o time) contra o backend LOCAL (nunca produção).
///
/// Roteiro: login → menu Suporte → abre atendimento → manda mensagem → espera
/// a resposta do time chegar pela conexão em tempo real (sem recarregar).
/// Quem responde é um script do lado do admin, rodando em paralelo contra a
/// mesma API: ele espera a mensagem "Mensagem do iPhone" e responde
/// "Resposta do time para o iPhone".
///
/// Rodar (backend em http://localhost:3000, terapeuta de teste já criado):
///   xcodebuild test -only-testing:TerapiaAcolherUITests/SupportFlowUITests
/// Fora da suíte padrão (`skippedTests` no `project.yml`) — comente a linha e
/// rode `xcodegen generate` antes, como no GatewayFlowUITests.
final class SupportFlowUITests: XCTestCase {
    let email = "maria@teste.local"
    let password = "Senha12345"
    let apiBaseURL = "http://localhost:3000"

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
        for rotulo in ["Agora Não", "Agora não", "Not Now", "Não Salvar", "Permitir", "Allow"] {
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

        let greeting = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Olá'")
        ).firstMatch
        XCTAssertTrue(greeting.waitForExistence(timeout: 40), "dashboard não carregou")
        _ = app.buttons["Agora Não"].waitForExistence(timeout: 8)
        fecharAvisoDoSistema()
    }

    private func abrirSuporte() {
        let menu = app.buttons["menuButton"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15), "menu não apareceu")
        for _ in 1 ... 4 {
            fecharAvisoDoSistema()
            if menu.isHittable { menu.tap() }
            let item = app.buttons["Suporte"].firstMatch
            if item.waitForExistence(timeout: 5) {
                if !item.isHittable { app.swipeUp() }
                item.tap()
                sleep(2)
                return
            }
        }
        XCTFail("seção Suporte não apareceu")
    }

    func testConversaEmTempoReal() throws {
        login()
        abrirSuporte()
        shoot("01-suporte")

        let criar = app.buttons["supportCreate"]
        if criar.waitForExistence(timeout: 10) {
            let editor = app.textViews.firstMatch
            XCTAssertTrue(editor.waitForExistence(timeout: 5), "caixa de texto do novo atendimento não apareceu")
            editor.tap()
            editor.typeText("Abrindo pelo iPhone: não consigo ver a agenda.")
            if !criar.isHittable { app.swipeUp() }
            criar.tap()
        } else {
            // Já havia um atendimento aberto: entra nele.
            let abrir = app.buttons["supportOpenTicket"]
            XCTAssertTrue(abrir.waitForExistence(timeout: 10), "nem novo atendimento nem conversa aberta")
            abrir.tap()
        }

        let composer = app.textFields["supportComposer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 20), "conversa não abriu")
        shoot("02-conversa")
        composer.tap()
        composer.typeText("Mensagem do iPhone")
        let enviar = app.buttons["supportSend"]
        XCTAssertTrue(enviar.waitForExistence(timeout: 5), "botão de enviar não apareceu")
        enviar.tap()

        let minha = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Mensagem do iPhone'")
        ).firstMatch
        XCTAssertTrue(minha.waitForExistence(timeout: 15), "mensagem enviada não apareceu na conversa")

        let resposta = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Resposta do time para o iPhone'")
        ).firstMatch
        let chegou = resposta.waitForExistence(timeout: 45)
        shoot("03-resposta")
        XCTAssertTrue(chegou, "resposta do time não chegou em tempo real")
    }

    /// Áudio gravado no simulador e foto da galeria (`xcrun simctl addmedia`).
    /// Precisa do atendimento aberto pelo teste anterior.
    func testMidiaAudioEFoto() throws {
        login()
        abrirSuporte()
        let abrir = app.buttons["supportOpenTicket"]
        if abrir.waitForExistence(timeout: 8) { abrir.tap() }
        let composer = app.textFields["supportComposer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 20), "conversa não abriu")

        // Áudio: grava ~3 s e envia.
        let gravar = app.buttons["Gravar áudio"]
        XCTAssertTrue(gravar.waitForExistence(timeout: 5), "botão de gravar não apareceu")
        gravar.tap()
        sleep(2)
        fecharAvisoDoSistema() // permissão do microfone
        let parar = app.buttons["Parar e enviar áudio"]
        if !parar.waitForExistence(timeout: 8) {
            // A permissão engoliu o primeiro toque.
            gravar.tap()
            XCTAssertTrue(parar.waitForExistence(timeout: 8), "gravação não começou")
        }
        sleep(3)
        parar.tap()
        shoot("04-audio-enviado")

        // Foto: primeira imagem da galeria.
        app.buttons["Anexar foto, vídeo ou arquivo"].tap()
        let fotoOuVideo = app.buttons["Foto ou vídeo"].firstMatch
        XCTAssertTrue(fotoOuVideo.waitForExistence(timeout: 5), "menu de anexo não abriu")
        fotoOuVideo.tap()
        sleep(3)
        // O seletor de fotos roda em outro processo, mas as miniaturas aparecem
        // na árvore do app com rótulo "Foto, <data>" (ou "Photo, …").
        let primeira = app.images.matching(
            NSPredicate(format: "label BEGINSWITH 'Foto' OR label BEGINSWITH 'Photo'")
        ).firstMatch
        XCTAssertTrue(primeira.waitForExistence(timeout: 15), "galeria não abriu")
        // A miniatura vem do processo do seletor e o XCUITest a acha "não
        // tocável"; o toque por coordenada chega nela.
        primeira.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        for rotulo in ["Adicionar", "Add", "Concluído", "Done"] where app.buttons[rotulo].exists {
            app.buttons[rotulo].tap()
            break
        }

        let resposta = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Recebi a foto'")
        ).firstMatch
        let chegou = resposta.waitForExistence(timeout: 60)
        shoot("05-midia")
        XCTAssertTrue(chegou, "o time não confirmou a foto")
    }
}
