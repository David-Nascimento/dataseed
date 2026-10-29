# app.rb
require "sinatra/base"
require "json"
require "csv"
require "faker"
require "securerandom"
require "i18n"

class DataSeed < Sinatra::Base
  SEGMENTS = %w[
    pf pj endereco contato produto cliente pedido transacao cartao endereco_internacional
  ].freeze

  SEGMENT_ALIASES = {
    "endereco_intl" => "endereco_internacional",
    "intl"          => "endereco_internacional"
  }.freeze

  FORMATS = %w[json csv].freeze

  # DDDs em uso no Brasil (Anatel)
  DDDS = [
    11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 24, 27, 28, 31, 32, 33, 34, 35, 37, 38,
    41, 42, 43, 44, 45, 46, 47, 48, 49, 51, 53, 54, 55, 61, 62, 63, 64, 65, 66, 67, 68, 69,
    71, 73, 74, 75, 77, 79, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 93, 94, 95, 96, 97, 98, 99
  ].freeze

  # O Faker não traduz "community" para pt-BR; usamos nomes de bairro comuns no Brasil
  BAIRROS = [
    "Centro", "Jardim América", "Vila Nova", "Boa Vista", "Santa Cecília", "Parque das Flores",
    "São José", "Jardim Europa", "Vila Mariana", "Aldeota", "Bela Vista", "Liberdade",
    "Jardim Botânico", "Santo Antônio", "Cidade Nova", "Vila Operária", "Jardim Paulista",
    "Industrial", "Santa Mônica", "Planalto", "Floresta", "Cristo Rei", "Esplanada", "Tijuca"
  ].freeze

  # Prefixos fictícios/de teste por bandeira (o cartão é coerente com a bandeira)
  BANDEIRAS = {
    "VISA"       => "400000",
    "MASTERCARD" => "510000",
    "ELO"        => "509000",
    "HIPERCARD"  => "606282"
  }.freeze

  DEFAULT_LOCALE = "pt-BR".freeze

  configure do
    set :environment, (ENV["RACK_ENV"] || :development).to_sym
    set :server, :puma
    set :max_count, (ENV["MAX_COUNT"] || 100).to_i
    set :public_folder, File.expand_path("public", __dir__)
    set :show_exceptions, false
    set :raise_errors, false
    enable :static

    Faker::Config.locale = DEFAULT_LOCALE
  end

  before do
    content_type "application/json"
    response.headers["Access-Control-Allow-Origin"] = "*"
  end

  # Erros inesperados nunca expõem stack trace
  error do
    content_type "application/json"
    status 500
    { error: "Erro interno ao gerar os dados." }.to_json
  end

  # -------------------- Helpers base --------------------
  helpers do
    def json_error(code, message)
      halt code, { "Content-Type" => "application/json" }, { error: message }.to_json
    end

    # RNG por requisição (evita vazamento de seed)
    def current_rng
      @rng ||= Random.new
    end

    def rand_digit; current_rng.rand(0..9); end

    # UUID v4 derivado do RNG da requisição: com seed, os IDs também se repetem
    def gerar_uuid
      bytes = current_rng.bytes(16).bytes
      bytes[6] = (bytes[6] & 0x0f) | 0x40
      bytes[8] = (bytes[8] & 0x3f) | 0x80
      hex = bytes.pack("C*").unpack1("H*")
      "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
    end

    def gerar_hex(n_bytes)
      current_rng.bytes(n_bytes).unpack1("H*")
    end

    def parse_count(param)
      return 1 if param.nil? || param.to_s.strip.empty?
      unless param.to_s.strip.match?(/\A\d+\z/)
        json_error 400, "Quantidade inválida. Use um número inteiro entre 1 e #{settings.max_count}."
      end
      param.to_i.clamp(1, settings.max_count)
    end

    def valid_locale?(locale)
      I18n.available_locales.map(&:to_s).include?(locale)
    end

    def email_para(nome)
      # Remove acentos antes de gerar o e-mail (evita "j#lia@...")
      Faker::Internet.email(name: I18n.transliterate(nome, locale: :en))
    end

    # ---------------- CPF/CNPJ ----------------
    def cpf_dv(nums, pos)
      soma = nums.each_with_index.sum { |n, i| n * (pos + 1 - i) }
      resto = soma % 11
      (resto < 2) ? 0 : 11 - resto
    end

    def gerar_cpf(mascarado: true)
      base = Array.new(9) { rand_digit }
      base = Array.new(9) { rand_digit } while base.uniq.size == 1 # 111.111.111-11 etc. são rejeitados por validadores
      d1 = cpf_dv(base, 9)
      d2 = cpf_dv(base + [d1], 10)
      digits = (base + [d1, d2]).join
      mascarado ? "#{digits[0..2]}.#{digits[3..5]}.#{digits[6..8]}-#{digits[9..10]}" : digits
    end

    def cnpj_dv(nums, pesos)
      soma = nums.each_with_index.sum { |n, i| n * pesos[i] }
      resto = soma % 11
      (resto < 2) ? 0 : 11 - resto
    end

    def gerar_cnpj(mascarado: true)
      base = Array.new(8) { rand_digit } + [0, 0, 0, 1]
      d1 = cnpj_dv(base, [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2])
      d2 = cnpj_dv(base + [d1], [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2])
      digits = (base + [d1, d2]).join
      mascarado ? "#{digits[0..1]}.#{digits[2..4]}.#{digits[5..7]}/#{digits[8..11]}-#{digits[12..13]}" : digits
    end

    # ---------------- Telefone/Endereço ----------------
    def gerar_telefone
      ddd = DDDS.sample(random: current_rng)
      sufixo = Array.new(8) { rand_digit }.join
      "(#{ddd}) 9#{sufixo[0..3]}-#{sufixo[4..7]}"
    end

    def gerar_endereco
      {
        rua: Faker::Address.street_name,
        numero: Faker::Number.number(digits: 3),
        complemento: [nil, "Apto 12", "Fundos", "Bloco B"].sample(random: current_rng),
        bairro: BAIRROS.sample(random: current_rng),
        cidade: Faker::Address.city,
        estado: Faker::Address.state_abbr,
        cep: Faker::Base.regexify(/\d{5}-\d{3}/)
      }
    end

    def gerar_endereco_internacional
      {
        tipo: "endereco_internacional",
        street: Faker::Address.street_address,
        secondary: [nil, Faker::Address.secondary_address].sample(random: current_rng),
        city: Faker::Address.city,
        state: Faker::Address.state,
        postal_code: Faker::Address.postcode,
        country: Faker::Address.country
      }
    end

    # ---------------- Pessoa Física/Jurídica ----------------
    def gerar_pf
      nome = Faker::Name.name
      {
        tipo: "pf",
        id: gerar_uuid,
        nome: nome,
        cpf: gerar_cpf(mascarado: true),
        data_nascimento: Faker::Date.birthday(min_age: 18, max_age: 80).strftime("%Y-%m-%d"),
        email: email_para(nome),
        telefone: gerar_telefone,
        endereco: gerar_endereco
      }
    end

    def gerar_pj
      nome_fantasia = Faker::Company.name
      {
        tipo: "pj",
        id: gerar_uuid,
        razao_social: "#{nome_fantasia} LTDA",
        nome_fantasia: nome_fantasia,
        cnpj: gerar_cnpj(mascarado: true),
        inscr_estadual: Faker::Number.number(digits: 12),
        email: email_para(nome_fantasia),
        telefone: gerar_telefone,
        endereco: gerar_endereco
      }
    end

    def gerar_contato
      nome = Faker::Name.name
      {
        tipo: "contato",
        id: gerar_uuid,
        nome: nome,
        email: email_para(nome),
        telefone: gerar_telefone
      }
    end

    # ---------------- Produto ----------------
    def gerar_produto
      {
        tipo: "produto",
        id_produto: gerar_uuid,
        sku: Faker::Alphanumeric.alphanumeric(number: 10).upcase,
        nome: Faker::Commerce.product_name,
        categoria: Faker::Commerce.department,
        preco: Faker::Commerce.price(range: 10.0..1500.0, as_string: false).round(2),
        estoque: current_rng.rand(0..500)
      }
    end

    # ---------------- Cliente ----------------
    def gerar_cliente
      perfis = %w[bronze prata ouro platina]
      canais = %w[email sms push whatsapp]
      {
        tipo: "cliente",
        id_cliente: gerar_uuid,
        pessoa: gerar_pf,
        score_credito: current_rng.rand(0..1000),
        limite_credito: (current_rng.rand * 20_000).round(2),
        renda_mensal: (current_rng.rand * 15_000 + 1_500).round(2),
        perfil: perfis.sample(random: current_rng),
        status: %w[ativo inativo pendente].sample(random: current_rng),
        preferencias: canais.sample(current_rng.rand(1..3), random: current_rng)
      }
    end

    # ---------------- Pedido ----------------
    def gerar_item_pedido
      produto = gerar_produto
      qty = current_rng.rand(1..5)
      {
        id_produto: produto[:id_produto],
        nome: produto[:nome],
        quantidade: qty,
        preco_unitario: produto[:preco],
        subtotal: (produto[:preco] * qty).round(2)
      }
    end

    def gerar_pedido
      itens = Array.new(current_rng.rand(1..5)) { gerar_item_pedido }
      {
        tipo: "pedido",
        id_pedido: gerar_uuid,
        cliente_id: gerar_uuid,
        data: Faker::Date.backward(days: 30).strftime("%Y-%m-%d"),
        itens: itens,
        total: itens.sum { |i| i[:subtotal] }.round(2),
        status: %w[novo pago enviado cancelado].sample(random: current_rng)
      }
    end

    # ---------------- Cartão (PAN Luhn, fictício) ----------------
    # Dígito verificador de Luhn para o número SEM o dígito final:
    # dobra-se o dígito mais à direita e, a partir dele, um sim um não.
    def luhn_check_digit(digits)
      sum = digits.reverse.each_with_index.sum do |d, i|
        n = i.even? ? d * 2 : d
        n > 9 ? n - 9 : n
      end
      (10 - (sum % 10)) % 10
    end

    def gerar_pan(bandeira: nil, masked: true)
      bandeira ||= BANDEIRAS.keys.sample(random: current_rng)
      bin = BANDEIRAS.fetch(bandeira)
      body = Array.new(15 - bin.length) { rand_digit } # 16 dígitos no total
      base_digits = bin.chars.map(&:to_i) + body
      full = (base_digits + [luhn_check_digit(base_digits)]).join
      masked ? "**** **** **** #{full[-4..]}" : full
    end

    def gerar_cartao
      bandeira = BANDEIRAS.keys.sample(random: current_rng)
      mm = format("%02d", current_rng.rand(1..12))
      yy = (Time.now.year % 100 + current_rng.rand(2..5)).to_s # 2 a 5 anos à frente
      {
        tipo: "cartao",
        id_cartao: gerar_uuid,
        nome_portador: Faker::Name.name,
        bandeira: bandeira,
        pan_mask: gerar_pan(bandeira: bandeira, masked: true),
        pan_hash: gerar_hex(16),
        validade: "#{mm}/#{yy}",
        cvv: format("%03d", current_rng.rand(0..999))
      }
    end

    # ---------------- Transação ----------------
    def gerar_transacao
      metodo = %w[cartao pix boleto].sample(random: current_rng)
      status =
        case metodo
        when "cartao" then current_rng.rand < 0.8 ? "aprovada" : "negada"
        when "pix"    then current_rng.rand < 0.95 ? "aprovada" : "pendente"
        else               current_rng.rand < 0.6 ? "pendente" : "aprovada"
        end
      {
        tipo: "transacao",
        id_transacao: gerar_uuid,
        pedido_id: gerar_uuid,
        metodo: metodo,
        valor: (current_rng.rand * 1500 + 20).round(2),
        nsu: Faker::Number.number(digits: 9),
        codigo_autorizacao: (metodo == "cartao" && status == "aprovada") ? Faker::Alphanumeric.alphanumeric(number: 6).upcase : nil,
        autorizada: status == "aprovada",
        status: status,
        cartao: (metodo == "cartao" ? gerar_cartao : nil)
      }
    end

    # ---------------- Include/Exclude (server-side) ----------------
    def split_fields(param)
      param.to_s.split(",").map(&:strip).reject(&:empty?)
    end

    def apply_include_exclude(obj, include_param, exclude_param)
      data = JSON.parse(JSON.generate(obj)) # cópia profunda com chaves string
      includes = split_fields(include_param)
      excludes = split_fields(exclude_param)

      if includes.any?
        filter_to_includes(data, includes)
      elsif excludes.any?
        remove_excludes(data, excludes)
      else
        data
      end
    end

    def filter_to_includes(obj, includes)
      result = {}
      includes.each do |path|
        parts = path.split(".")
        node = obj
        found = parts.all? do |p|
          next false unless node.is_a?(Hash) && node.key?(p)
          node = node[p]
          true
        end
        next unless found

        target = result
        parts[0..-2].each { |p| target = (target[p] ||= {}) }
        target[parts[-1]] = node
      end
      result
    end

    def remove_excludes(obj, excludes)
      excludes.each do |path|
        parts = path.split(".")
        parent = obj
        parts[0..-2].each do |p|
          break unless parent.is_a?(Hash)
          parent = parent[p]
        end
        parent.delete(parts[-1]) if parent.is_a?(Hash)
      end
      obj
    end

    # ---------------- CSV ----------------
    def to_csv(array)
      headers = array.flat_map(&:keys).uniq
      CSV.generate(col_sep: ";") do |csv|
        csv << headers
        array.each do |row|
          csv << headers.map { |h| (row[h].is_a?(Hash) || row[h].is_a?(Array)) ? JSON.generate(row[h]) : row[h] }
        end
      end
    end

    # ---------------- Builder ----------------
    def segment_builder(segment)
      case segment
      when "pf"                     then method(:gerar_pf)
      when "pj"                     then method(:gerar_pj)
      when "endereco"               then -> { { tipo: "endereco" }.merge(gerar_endereco) }
      when "contato"                then method(:gerar_contato)
      when "produto"                then method(:gerar_produto)
      when "cliente"                then method(:gerar_cliente)
      when "pedido"                 then method(:gerar_pedido)
      when "transacao"              then method(:gerar_transacao)
      when "cartao"                 then method(:gerar_cartao)
      when "endereco_internacional" then method(:gerar_endereco_internacional)
      end
    end
  end

  # ---------------- Rotas ----------------
  get "/" do
    content_type "text/html"
    send_file File.join(settings.public_folder, "index.html")
  end

  get "/ui" do
    content_type "text/html"
    send_file File.join(settings.public_folder, "index.html")
  end

  get "/api" do
    {
      nome: "DataSeed",
      status: "ok",
      segments: SEGMENTS,
      max_count: settings.max_count,
      params: {
        segment: SEGMENTS.join("|"),
        count: "1..#{settings.max_count}",
        format: FORMATS.join("|"),
        locale: "pt-BR|en|es|fr|de|... (locales do Faker)",
        mode: "simple|advanced (opcional; com simple, seed/include/exclude são ignorados)",
        seed: "opcional (reprodutibilidade)",
        include: "opcional (whitelist de campos, suporta dot notation)",
        exclude: "opcional (remove campos, suporta dot notation)"
      }
    }.to_json
  end

  get "/health" do
    { status: "ok", time: Time.now.utc.iso8601 }.to_json
  end

  get "/generate" do
    raw_segment = (params["segment"] || "pf").downcase.strip
    segment = SEGMENT_ALIASES.fetch(raw_segment, raw_segment)
    format  = (params["format"] || "json").downcase.strip
    locale  = (params["locale"] || DEFAULT_LOCALE).strip
    locale  = DEFAULT_LOCALE if locale.empty?
    mode    = (params["mode"] || "").downcase

    # Valida tudo antes de gerar qualquer dado
    json_error 400, "Segmento inválido. Use: #{SEGMENTS.join(', ')}." unless SEGMENTS.include?(segment)
    json_error 400, "Formato inválido. Use json ou csv." unless FORMATS.include?(format)
    json_error 400, "Locale \"#{locale}\" não é suportado. Exemplos válidos: pt-BR, en, es, fr, de." unless valid_locale?(locale)
    count = parse_count(params["count"])

    # Opções avançadas valem sempre, exceto quando o front pede mode=simple
    seed          = params["seed"].to_s.strip
    include_param = params["include"]
    exclude_param = params["exclude"]
    if mode == "simple"
      seed = ""
      include_param = nil
      exclude_param = nil
    end
    if !seed.empty? && !seed.match?(/\A-?\d+\z/)
      json_error 400, "Seed inválida. Use um número inteiro."
    end

    begin
      Faker::Config.locale = locale
      @rng = seed.empty? ? Random.new : Random.new(seed.to_i)
      Faker::Config.random = @rng

      builder = segment_builder(segment)
      builder = method(:gerar_endereco_internacional) if segment == "endereco" && locale != DEFAULT_LOCALE

      data = Array.new(count) do
        record = builder.call
        if include_param.to_s.strip != "" || exclude_param.to_s.strip != ""
          record = apply_include_exclude(record, include_param, exclude_param)
        end
        record
      end

      if format == "csv"
        content_type "text/csv"
        headers["Content-Disposition"] = "attachment; filename=#{segment}_#{Time.now.to_i}.csv"
        to_csv(data)
      else
        { count: data.size, segment: segment, data: data }.to_json
      end
    ensure
      Faker::Config.random = nil
      Faker::Config.locale = DEFAULT_LOCALE
      @rng = nil
    end
  end

  # CORS (preflight)
  options "*" do
    response.headers["Access-Control-Allow-Methods"] = "GET,OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    200
  end

  not_found do
    content_type "application/json"
    { error: "Rota não encontrada. Veja GET /api para a lista de endpoints." }.to_json
  end
end
