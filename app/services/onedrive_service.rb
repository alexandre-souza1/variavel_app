require "oauth2"
require "faraday"

class OnedriveService

  require "net/http"
  require "json"

  GRAPH_URL = "https://graph.microsoft.com/v1.0"
  SITE_ID = "7z4kss.sharepoint.com,bb4aea8f-3ee8-4341-a1cd-c709509ca7fe,12d5fb7d-7c2c-40f1-990f-983bbebf0bc1"
  DRIVE_ID = "b!j-pKu-g-QUOhzccJUJyn_n371RIsfPFAmQ-YO76_C8G-XglJFqtZSo9Rj4qwe_5Y"

  def initialize
    @client_id     = ENV["AZURE_CLIENT_ID"]
    @client_secret = ENV["AZURE_CLIENT_SECRET"]
    @tenant_id     = ENV["AZURE_TENANT_ID"]
    @user_id       = ENV["AZURE_USER_ID"]
    @access_token  = get_access_token&.token
  end

  # === Token ===
  def get_access_token
    client = OAuth2::Client.new(
      @client_id,
      @client_secret,
      site: "https://login.microsoftonline.com",
      token_url: "/#{@tenant_id}/oauth2/v2.0/token"
    )

    client.client_credentials.get_token(scope: "https://graph.microsoft.com/.default")
  rescue => e
    Rails.logger.error("Erro ao obter token: #{e.message}")
    nil
  end

    # Upload direto do conteúdo binário para SharePoint
    def upload_sharepoint_temp(file_content, remote_name, folder_path = "")
      # Criar nome seguro com timestamp para evitar duplicatas
      timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
      safe_name = "invoice_#{timestamp}_#{SecureRandom.hex(4)}#{File.extname(remote_name)}"

      # Montar o caminho completo da pasta - INCLUIR "Invoices/" no início
      base_folder = "Invoices"
      full_path = if folder_path.present?
                    "#{base_folder}/#{folder_path}/#{safe_name}"
                  else
                    "#{base_folder}/#{safe_name}"
                  end

      url = URI("#{GRAPH_URL}/sites/#{SITE_ID}/drives/#{DRIVE_ID}/root:/#{full_path}:/content")

      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true

      request = Net::HTTP::Put.new(url)
      request["Authorization"] = "Bearer #{@access_token}"
      request["Content-Type"] = "application/octet-stream"
      request.body = file_content.force_encoding("BINARY")

      response = http.request(request)

      if response.code.to_i.between?(200,299)
        Rails.logger.info("Upload realizado com sucesso! -> #{JSON.parse(response.body)['webUrl']}")
        JSON.parse(response.body)
      else
        Rails.logger.error("Erro no upload (sharepoint): #{response.code} - #{response.body}")
        nil
      end
    end

  # === Cria a pasta Invoices (somente em OneDrive de usuário) ===
  def ensure_invoices_folder
    access_token = token&.token
    return nil unless access_token

    conn = Faraday.new(url: GRAPH_URL)

    response = conn.get("/users/#{@user_id}/drive/root/children?$filter=name eq 'Invoices'") do |req|
      req.headers["Authorization"] = "Bearer #{access_token}"
    end

    if response.success?
      data = JSON.parse(response.body)
      return data['value'][0]['id'] if data['value'].any?
    end

    response = conn.post("/users/#{@user_id}/drive/root/children") do |req|
      req.headers["Authorization"] = "Bearer #{access_token}"
      req.headers["Content-Type"] = "application/json"
      req.body = {
        name: "Invoices",
        folder: {},
        "@microsoft.graph.conflictBehavior": "rename"
      }.to_json
    end

    handle_response(response, "criação de pasta Invoices")&.dig("id")
  end

  # === Testes ===
  def test_user_drive
    access_token = token&.token
    return "Token não disponível" unless access_token

    conn = Faraday.new(url: GRAPH_URL)
    response = conn.get("/users/#{@user_id}/drive") do |req|
      req.headers["Authorization"] = "Bearer #{access_token}"
    end

    if response.success?
      data = JSON.parse(response.body)
      "✅ OneDrive conectado! Espaço livre: #{(data['quota']['remaining'] / 1024 / 1024 / 1024).round(2)} GB"
    else
      "❌ Erro OneDrive: #{response.status} - #{response.body[0..200]}"
    end
  end

  def test_sharepoint
    access_token = token&.token
    return "Token não disponível" unless access_token

    conn = Faraday.new(url: GRAPH_URL)
    response = conn.get("/sites/#{SITE_ID}/drives/#{DRIVE_ID}") do |req|
      req.headers["Authorization"] = "Bearer #{access_token}"
    end

    if response.success?
      data = JSON.parse(response.body)
      "✅ SharePoint conectado! Biblioteca: #{data['name']}"
    else
      "❌ Erro SharePoint: #{response.status} - #{response.body[0..200]}"
    end
  end

  private

  def handle_response(response, action)
    if response.success?
      JSON.parse(response.body)
    else
      Rails.logger.error("Erro no #{action}: #{response.status} - #{response.body}")
      nil
    end
  rescue => e
    Rails.logger.error("Erro no #{action}: #{e.message}")
    nil
  end
end
