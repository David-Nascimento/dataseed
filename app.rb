
# app.rb
require "sinatra/base"
require "json"
require "csv"
require "faker"
require "securerandom"

class DataSeed < Sinatra::Base
  configure do
    set :environment, (ENV["RACK_ENV"] || :development).to_sym
    set :server, :puma
    set :max_count, (ENV["MAX_COUNT"] || 100).to_i
    set :public_folder, File.expand_path("../public", __FILE__)
    enable :static

    Faker::Config.locale = "pt-BR"
  end

  before do
    content_type "application/json"
  end

  # -------------------- Helpers base --------------------
  helpers do
    # RNG por requisição (evita vazamento de seed)
    def current_rng
      @rng ||= Random.new
    end

    def rand_digit; current_rng.rand(0..9); end

    def clamp_count(param)
      count = (param || "1").to_i
      max = settings.max_count
      [[count, 1].max, max].min
    end

    # ---------------- CPF/CNPJ ----------------
    def cpf_dv(nums, pos)
      soma = nums.each_with_index.sum { |n, i| n * (pos + 1 - i) }
      resto = soma % 11
      (resto < 2) ? 0 : 11 - resto
    end

    def gerar_cpf(mascarado: true)
      base = Array.new(9) { rand_digit }
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
      d1 = cnpj_dv(base, [5,4,3,2,9,8,7,6,5,4,3,2])
      d2 = cnpj_dv(base + [d1], [6,5,4,3,2,9,8,7,6,5,4,3,2])
      digits = (base + [d1, d2]).join
      mascarado ? "#{digits[0..1]}.#{digits[2..4]}.#{digits[5..7]}/#{digits[8..11]}-#{digits[12..13]}" : digits
    end

    # ---------------- Telefone/Endereço ----------------
    def gerar_telefone
      ddd = current_rng.rand(10..99) # evita 00/01
      sufixo = Array.new(8) { rand_digit }.join
      "(#{ddd}) 9#{sufixo[0..3]}-#{sufixo[4..7]}"
    end

    def gerar_endereco(locale: "pt-BR")
      # Para internacional, o locale será ajustado externamente em Faker::Config.locale
      {
        rua: Faker::Address.street_name,
        numero: Faker::Number.number(digits: 3),
        complemento: [nil, "Apto 12", "Fundos", "Bloco B"].sample(random: current_rng),
        bairro: Faker::Address.community,
        cidade: Faker::Address.city,
        estado: Faker::Address.state_abbr,
        cep: Faker::Base.regexify(/\d{5}-\d{3}/)
      }
    end

    def gerar_endereco_internacional
      {
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
      email = Faker::Internet.email(name: nome)
      {
        tipo: "pf",
        id: SecureRandom.uuid,
        nome: nome,
        cpf: gerar_cpf(mascarado: true),
        data_nascimento: Faker::Date.birthday(min_age: 18, max_age: 80).strftime("%Y-%m-%d"),
        email: email,
        telefone: gerar_telefone,
        endereco: gerar_endereco
      }
    end

    def gerar_pj
      nome_fantasia = Faker::Company.name
      {
        tipo: "pj",
        id: SecureRandom.uuid,
        razao_social: "#{nome_fantasia} LTDA",
        nome_fantasia: nome_fantasia,
        cnpj: gerar_cnpj(mascarado: true),
        inscr_estadual: Faker::Number.number(digits: 12),
        email: Faker::Internet.email(name: nome_fantasia),
        telefone: gerar_telefone,
        endereco: gerar_endereco
      }
    end

    def gerar_contato
      nome = Faker::Name.name
      {
        tipo: "contato",
        id: SecureRandom.uuid,
        nome: nome,
        email: Faker::Internet.email(name: nome),
        telefone: gerar_telefone
      }
    end

    # ---------------- Produto ----------------
    def gerar_produto
      nome = Faker::Commerce.product_name
      {
        tipo: "produto",
        id_produto: SecureRandom.uuid,
        sku: Faker::Alphanumeric.alphanumeric(number: 10).upcase,
        nome: nome,
        categoria: Faker::Commerce.department,
        preco: (Faker::Commerce.price(range: 10.0..1500.0, as_string: false)).round(2),
        estoque: current_rng.rand(0..500)
      }
    end

    # ---------------- Cliente ----------------

    def gerar_cliente
      pf = gerar_pf
      perfis = %w[bronze prata ouro platina]
      canais = %w[email sms push whatsapp]
      {
        tipo: "cliente",
        id_cliente: SecureRandom.uuid,
        pessoa: pf,
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
      subtotal = (produto[:preco] * qty).round(2)
      {
        id_produto: produto[:id_produto],
        nome: produto[:nome],
        quantidade: qty,
        preco_unitario: produto[:preco],
        subtotal: subtotal
      }
    end

    def gerar_pedido
      itens = Array.new(current_rng.rand(1..5)) { gerar_item_pedido }
      total = itens.sum { |i| i[:subtotal] }.round(2)
      {
        tipo: "pedido",
        id_pedido: SecureRandom.uuid,
        cliente_id: SecureRandom.uuid,
        data: Faker::Date.backward(days: 30).strftime("%Y-%m-%d"),
        itens: itens,
        total: total,
        status: %w[novo pago enviado cancelado].sample(random: current_rng)
      }
    end

    # ---------------- Cartão (PAN Luhn, seguro/fictício) ----------------
    def luhn_check_digit(digits)
      sum = digits.reverse.each_with_index.sum do |d, i|
        n = d
        n *= 2 if i.odd?
        n = (n - 9) if n > 9
        n
      end
      (10 - (sum % 10)) % 10
    end

    def gerar_pan(masked: true)
      # BINs fictícios (não correspondem a emissores reais)
      bins = %w[400000 510000 220000 670000] # Visa-like, MC-like, MIR-like, Maestro-like (fictício)
      bin = bins.sample(random: current_rng)
      body = Array.new(9) { rand_digit } # total 16 = 6 (bin) + 9 (body) + 1 (check)
      base_digits = (bin.chars.map(&:to_i) + body)
      check = luhn_check_digit(base_digits)
      full = (base_digits + [check]).join
      return "**** **** **** #{full[-4..-1]}" if masked
      full
    end

    def gerar_cartao
      nome = Faker::Name.name
      mm = format("%02d", current_rng.rand(1..12))
      yy = (Time.now.year % 100 + current_rng.rand(2..5)).to_s # 2-5 anos à frente
      {
        tipo: "cartao",
        id_cartao: SecureRandom.uuid,
        nome_portador: nome,
        pan_mask: gerar_pan(masked: true),
        pan_hash: SecureRandom.hex(16), # representação segura (fictícia)
        validade: "#{mm}/#{yy}",
        cvv: format("%03d", current_rng.rand(0..999)),
        bandeira: %w[VISA MASTERCARD ELO HIPERCARD].sample(random: current_rng)
      }
    end

    # ---------------- Transação ----------------
    def gerar_transacao
      metodo = %w[cartao pix boleto].sample(random: current_rng)
      valor = (current_rng.rand * 1500 + 20).round(2)
      {
        tipo: "transacao",
        id_transacao: SecureRandom.uuid,
        pedido_id: SecureRandom.uuid,
        metodo: metodo,
        valor: valor,
        nsu: Faker::Number.number(digits: 9),
        codigo_autorizacao: metodo == "cartao" ? Faker::Alphanumeric.alphanumeric(number: 6).upcase : nil,
        autorizada: metodo == "cartao" ? [true, false].sample(random: current_rng) : (metodo == "pix"),
        status: %w[aprovada negada pendente].sample(random: current_rng),
        cartao: (metodo == "cartao" ? gerar_cartao : nil)
      }
    end

    # ---------------- Endereço internacional ----------------
    def gerar_endereco_intl
      gerar_endereco_internacional
    end

    # ---------------- Include/Exclude (server-side) ----------------
    def apply_include_exclude(obj, include_param, exclude_param)
      # clone para não mutar original
      data = JSON.parse(JSON.generate(obj))

      if include_param && !include_param.strip.empty?
        includes = include_param.split(",").map(&:strip).reject(&:empty?)
        # mantém apenas chaves listadas (suporta dot notation para nested)
        data = filter_to_includes(data, includes)
      elsif exclude_param && !exclude_param.strip.empty?
        excludes = exclude_param.split(",").map(&:strip).reject(&:empty?)
        data = remove_excludes(data, excludes)
      end

      data
    end

    def filter_to_includes(obj, includes)
      # Cria um novo objeto contendo apenas caminhos (dot notation) e top-level
      result = {}
      includes.each do |path|
        parts = path.split(".")
        node = obj
        ok = true
        parts.each do |p|
          if node.is_a?(Hash) && node.key?(p)
            node = node[p]
          else
            ok = false
            break
          end
        end
        next unless ok
        # montar no result
        target = result
        parts[0..-2].each do |p|
          target[p] ||= {}
          target = target[p]
        end
        target[parts[-1]] = node
      end
      # também permitir includes top-level simples
      includes.each do |k|
        next if k.include?(".")
        result[k] ||= obj[k] if obj.key?(k)
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
        key = parts[-1]
        if parent.is_a?(Hash) && parent.key?(key)
          parent.delete(key)
        end
      end
      obj
    end

    # ---------------- CSV ----------------
    def to_csv(array)
      # União de cabeçalhos top-level de todos os registros
      headers = array.map(&:keys).flatten.uniq
      CSV.generate(col_sep: ";") do |csv|
        csv << headers
        array.each do |row|
          csv << headers.map { |h| row[h].is_a?(Hash) || row[h].is_a?(Array) ? JSON.generate(row[h]) : row[h] }
        end
      end
    end

    # ---------------- Builder ----------------

    def segment_builder(segment)
      case segment
      when "pf"                    then method(:gerar_pf)
      when "pj"                    then method(:gerar_pj)
      when "endereco"              then method(:gerar_endereco)
      when "contato"               then method(:gerar_contato)
      when "produto"               then method(:gerar_produto)
      when "cliente"               then method(:gerar_cliente)
      when "pedido"                then method(:gerar_pedido)
      when "transacao"             then method(:gerar_transacao)
      when "cartao"                then method(:gerar_cartao)
      when "endereco_internacional", "endereco_intl", "intl" then method(:gerar_endereco_internacional)
      else
        halt 400, { error: "Segmento inválido. Use: pf, pj, endereco, contato, produto, cliente, pedido, transacao, cartao, endereco_internacional." }.to_json
      end
    end
  end

  # ---------------- Rotas ----------------
  get "/" do
    content_type "text/html"
    send_file File.join(settings.public_folder, "index.html")
  end
  
  get "/api" do
    {
      nome: "DataSeed",
      status: "ok",
      segments: %w[
        pf pj endereco contato produto cliente pedido transacao cartao endereco_internacional
      ],
      params: {
        segment: "pf|pj|endereco|contato|produto|cliente|pedido|transacao|cartao|endereco_internacional",
        count: "1..#{settings.max_count}",
        format: "json|csv",
        locale: "pt-BR|en|es|fr|de|... (Faker locales)",
        seed: "opcional (reprodutibilidade)",
        include: "opcional (whitelist de campos, suporta dot notation)",
        exclude: "opcional (remove campos, suporta dot notation)"
      }
    }.to_json
  end

  # Health
  get "/health" do
    content_type "application/json"
    { status: "ok", time: Time.now.utc }.to_json
  end

  # Geração

  # app.rb (dentro da classe DataSeed)

  get "/generate" do
    segment = (params["segment"] || "pf").downcase
    count   = clamp_count(params["count"])
    format  = (params["format"] || "json").downcase
    locale  = params["locale"] || "pt-BR"

    # 🔒 modo explícito vindo do front (simple|advanced); default simple
    mode    = (params["mode"] || "simple").downcase

    # avançado (apenas se mode=advanced)
    seed          = params["seed"]
    include_param = params["include"]
    exclude_param = params["exclude"]

    # 🔐 Nunca considere avançados quando mode=simple
    if mode == "simple"
      seed = nil
      include_param = nil
      exclude_param = nil
    end

    Faker::Config.locale = locale

    begin
      # RNG por requisição — sem srand; isolado por mode
      @rng = seed ? Random.new(seed.to_i) : Random.new
      Faker::Config.random = @rng

      builder = segment_builder(segment)

      data = Array.new(count) do
        record = builder.call
        # ajuste especial: endereco BR com locale != pt-BR => internacional
        if segment == "endereco" && locale != "pt-BR"
          record = gerar_endereco_internacional
          record[:tipo] = "endereco_internacional"
        end

        # include/exclude server-side (apenas se mode=advanced e params presentes)
        if include_param && !include_param.strip.empty?
          record = apply_include_exclude(record, include_param, nil)
        elsif exclude_param && !exclude_param.strip.empty?
          record = apply_include_exclude(record, nil, exclude_param)
        end

        record
      end

      case format
      when "json"
        content_type "application/json"
        { count: data.size, segment: segment, data: data }.to_json
      when "csv"
        content_type "text/csv"
        headers["Content-Disposition"] = "attachment; filename=#{segment}_#{Time.now.to_i}.csv"
        to_csv(data)
      else
        halt 400, { error: "Formato inválido. Use json ou csv." }.to_json
      end
    ensure
      Faker::Config.random = nil
      @rng = nil
    end
  end

    # CORS
  options "*" do
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET,OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    200
  end

  before do
    response.headers["Access-Control-Allow-Origin"] = "*"
  end

  # Se quiser que / sirva a UI:
  get "/ui" do
    content_type "text/html"
    send_file File.join(settings.public_folder, "index.html")
  end
end