import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static values = { userId: Number }

  connect() {
    console.log("🔌 Reconnect Controller conectado, user:", this.userIdValue)

    if (this.userIdValue) {
      this.initializeActionCable()
    }
  }

  initializeActionCable() {
    try {
      // Cria o consumer se não existir
      if (typeof App === 'undefined') {
        window.App = {}
      }

      if (!App.cable) {
        App.cable = createConsumer()
        console.log("✅ Action Cable consumer criado")
      }

      // Cria a subscription
      this.subscription = App.cable.subscriptions.create(
        {
          channel: "UserChannel",
          user_id: this.userIdValue
        },
        {
          connected: () => {
            console.log("✅ Conectado ao UserChannel para usuário:", this.userIdValue)
          },

          disconnected: () => {
            console.log("❌ Desconectado do UserChannel")
          },

          received: (data) => {
            console.log("📨 Mensagem recebida no Reconnect Controller:", data)
            this.processMessage(data)
          }
        }
      )

    } catch (error) {
      console.error("❌ Erro ao inicializar Action Cable:", error)
    }
  }

  processMessage(data) {
    // 1. Processa HTML da progress bar
    if (data.html) {
      console.log("🔄 Atualizando progress bar...")
      this.updateProgressBar(data.html)
    }

    // 2. Processa redirect com dados estruturados
    if (data.redirect_url) {
      console.log("🔄 Redirecionando para:", data.redirect_url)
      this.redirectToUrl(data.redirect_url, data.redirect_delay || 2000)
    }
  }

  updateProgressBar(html) {
    // Usa o próprio elemento do controller como container
    this.element.innerHTML = html
    console.log("✅ Progress bar atualizada no Reconnect Controller")
  }

  executeScript(script) {
    try {
      // Executa o script diretamente
      eval(script)
      console.log("✅ Script executado com sucesso")
    } catch (error) {
      console.error("❌ Erro ao executar script:", error)
    }
  }

  // NOVO MÉTODO PARA REDIRECT
  redirectToUrl(url, delay = 2000) {
    console.log(`🔀 Redirecionando para ${url} em ${delay}ms...`)
    setTimeout(() => {
      console.log("🎯 Executando redirect...")
      window.location.href = url
    }, delay)
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
      console.log("📪 Subscription cancelada")
    }
  }
};
