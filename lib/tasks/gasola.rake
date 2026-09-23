namespace :gasola do
  desc 'Sincroniza consumo do período atual e anterior (ou FROM/TO em ISO 8601)'
  task sync: :environment do
    from = ENV['FROM'].present? ? Time.zone.iso8601(ENV['FROM']) : Gasola::Sync.default_from
    to = ENV['TO'].present? ? Time.zone.iso8601(ENV['TO']) : Time.current
    count = Gasola::Sync.new.call(from: from, to: to)
    puts(count.nil? ? 'Sincronização já em andamento.' : "Gasola: #{count} abastecimentos sincronizados.")
  end

  desc 'Mantém a sincronização do Gasola a cada hora'
  task work: :environment do
    abort 'Configure GASOLA_API_TOKEN antes de iniciar.' if ENV['GASOLA_API_TOKEN'].blank?
    loop do
      begin
        count = Gasola::Sync.new.call
        Rails.logger.info("Gasola: #{count} abastecimentos sincronizados.") if count
      rescue StandardError => error
        # Never log response bodies, credentials or personal data.
        Rails.logger.error("Falha na sincronização Gasola (#{error.class.name}). Nova tentativa em uma hora.")
      end
      sleep 3600
    end
  end
end
