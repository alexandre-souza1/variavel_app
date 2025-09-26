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

  # Método para obter URL de download direta (sem autenticação necessária)
  def get_direct_download_url(sharepoint_url)
    return nil unless @access_token

    # Primeiro, encontra o ID do item pelo caminho
    item_id = find_item_id_by_path(extract_path_from_url(sharepoint_url))
    return nil unless item_id

    begin
      # Obtém a URL de download direta temporária
      url = URI("#{GRAPH_URL}/sites/#{SITE_ID}/drives/#{DRIVE_ID}/items/#{item_id}")

      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(url)
      request["Authorization"] = "Bearer #{@access_token}"

      response = http.request(request)

      if response.code.to_i == 200
        data = JSON.parse(response.body)
        # Esta URL permite download sem autenticação
        download_url = data["@microsoft.graph.downloadUrl"]

        if download_url
          Rails.logger.info("✅ URL de download direta obtida: #{download_url}")
          return download_url
        else
          Rails.logger.error("URL de download não encontrada na resposta")
          return nil
        end
      else
        Rails.logger.error("Erro ao obter URL de download: #{response.code} - #{response.body}")
        nil
      end
    rescue => e
      Rails.logger.error("Erro no get_direct_download_url: #{e.message}")
      nil
    end
  end

  # Método para criar um link compartilhável anônimo + URL de download
  def create_anonymous_download_link(sharepoint_url)
    return nil unless @access_token

    item_id = find_item_id_by_path(extract_path_from_url(sharepoint_url))
    return nil unless item_id

    begin
      # Primeiro, cria um link de visualização anônimo
      url = URI("#{GRAPH_URL}/sites/#{SITE_ID}/drives/#{DRIVE_ID}/items/#{item_id}/createLink")

      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(url)
      request["Authorization"] = "Bearer #{@access_token}"
      request["Content-Type"] = "application/json"
      request.body = {
        type: "view",
        scope: "anonymous"
      }.to_json

      response = http.request(request)

      if response.code.to_i == 200 || response.code.to_i == 201
        data = JSON.parse(response.body)
        web_url = data["link"]["webUrl"]

        # Converte para URL de download
        download_url = web_url + '?download=1'
        Rails.logger.info("✅ Link anônimo criado: #{download_url}")
        return download_url
      else
        Rails.logger.error("Erro ao criar link anônimo: #{response.code} - #{response.body}")
        nil
      end
    rescue => e
      Rails.logger.error("Erro no create_anonymous_download_link: #{e.message}")
      nil
    end
  end

  # === Testes ===
  def test_user_drive
    return "Token não disponível" unless @access_token

    conn = Faraday.new(url: GRAPH_URL)
    response = conn.get("/users/#{@user_id}/drive") do |req|
      req.headers["Authorization"] = "Bearer #{@access_token}"
    end

    if response.success?
      data = JSON.parse(response.body)
      "✅ OneDrive conectado! Espaço livre: #{(data['quota']['remaining'] / 1024 / 1024 / 1024).round(2)} GB"
    else
      "❌ Erro OneDrive: #{response.status} - #{response.body[0..200]}"
    end
  end

  def test_sharepoint
    return "Token não disponível" unless @access_token

    conn = Faraday.new(url: GRAPH_URL)
    response = conn.get("/sites/#{SITE_ID}/drives/#{DRIVE_ID}") do |req|
      req.headers["Authorization"] = "Bearer #{@access_token}"
    end

    if response.success?
      data = JSON.parse(response.body)
      "✅ SharePoint conectado! Biblioteca: #{data['name']}"
    else
      "❌ Erro SharePoint: #{response.status} - #{response.body[0..200]}"
    end
  end

  private

  def extract_path_from_url(sharepoint_url)
    # Extrai o caminho do arquivo da URL do SharePoint
    uri = URI.parse(sharepoint_url)
    path = uri.path

    # Remove o prefixo do site para obter o caminho relativo
    site_prefix = "/sites/nf_budget_app/Documentos%20Compartilhados"
    if path.start_with?(site_prefix)
      path = path[site_prefix.length..-1]
    end

    URI.decode_www_form_component(path)
  end

  def find_item_id_by_path(file_path)
    return nil if file_path.blank?

    begin
      # Busca o item pelo caminho no SharePoint
      encoded_path = URI.encode_www_form_component(file_path).gsub('+', '%20')
      url = URI("#{GRAPH_URL}/sites/#{SITE_ID}/drives/#{DRIVE_ID}/root:#{encoded_path}")

      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(url)
      request["Authorization"] = "Bearer #{@access_token}"

      response = http.request(request)

      if response.code.to_i == 200
        data = JSON.parse(response.body)
        data["id"]
      else
        Rails.logger.error("Erro ao buscar item por caminho: #{response.code} - #{response.body}")
        nil
      end
    rescue => e
      Rails.logger.error("Erro no find_item_id_by_path: #{e.message}")
      nil
    end
  end

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
