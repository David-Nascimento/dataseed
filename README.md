# DataSeed — Portal de Geração de Massa de Dados (Ruby + Sinatra + Puma)

Gerador de dados **fictícios** e **realistas** para auxiliar **QA** e **Devs** em testes de integração, automação e performance.

Suporta:
- **PF/PJ**, **contato**, **endereço BR**, **endereço internacional**
- **produto**, **cliente**, **pedido**, **transação**, **cartão** (PAN Luhn, mascarado)
- Exportação em **JSON** e **CSV**
- **Seed determinística por requisição** (sem vazar entre chamadas)
- **Include/Exclude (server-side)** com **dot notation** para campos aninhados

> ⚠️ **Privacidade e uso**: Todos os dados gerados são fictícios e não pertencem a pessoas reais; CPF/CNPJ/PAN passam em regras de dígitos por realismo, mas não representam documentos/cartões de indivíduos ou empresas. Use exclusivamente em ambientes de teste.

---

## Sumário

- Arquitetura
- Requisitos
- Instalação
- Como iniciar
- Estrutura de pastas
- Configurações
- Endpoints
- Parâmetros
- Segmentos suportados
- Seed determinística (por requisição)
- Include/Exclude (server-side)
- Formato CSV
- Front-end (UI)
- Exemplos de uso (`curl`)
- Docker
- Puma (config opcional)
- Troubleshooting
- Boas práticas
- Licença

---

## Arquitetura

- **API**: Ruby + **Sinatra** (modular, `Sinatra::Base`) — gera dados e serve estáticos.
- **Servidor HTTP**: **Puma**.
- **Geração**: **Faker** (dados realistas); algoritmos próprios para **CPF/CNPJ** e **PAN (Luhn)**.
- **Exportação**: JSON e CSV. Em CSV, objetos/arrays vêm **serializados como JSON** na célula.
- **UI**: HTML/CSS/JS **vanilla** em `/public`.
- **CORS**: habilitado para `GET` e `OPTIONS`.

---

## Requisitos

- **Ruby** 3.3+ (testado em `ruby 3.3.4`)
- **Bundler**
- macOS/Linux (desenvolvimento local)
- (Opcional) **Docker**

---

## Instalação

1) **Clone o repositório**
```bash
git clone <URL_DO_REPO> DataSeed
cd DataSeed
````

2.  **Instale as dependências**

```bash
bundle install
```

**Gemfile esperado:**

```ruby
source "https://rubygems.org"

ruby "~> 3.3"

gem "sinatra", require: "sinatra/base"
gem "puma"
gem "faker"
gem "rack-cors"
gem "csv" # compat com Ruby 3.4+ (csv deixa de ser default gem)
```

***

## Como iniciar

### Opção A — `rackup` (recomendado em dev)

```bash
bundle exec rackup -p 9292
```

*   UI: `http://localhost:9292/index.html`
*   API: `http://localhost:9292/generate`
*   Health: `http://localhost:9292/health`

### Opção B — `puma` lendo `config.ru`

```bash
bundle exec puma -p 9292 config.ru
```

> **Dica**: Se você rodar `puma` sem indicar `config.ru` e estiver fora do diretório do projeto, verá `No application configured, nothing to run`. Rode na pasta correta ou indique o arquivo.

***

## Estrutura de pastas

    DataSeed/
    ├─ app.rb          # API + lógica de geração de dados
    ├─ config.ru       # Rack config: run DataSeed
    ├─ Gemfile
    └─ public/         # Front-end
       ├─ index.html
       ├─ styles.css
       └─ app.js

***

## Configurações

Trecho principal em `app.rb`:

```ruby
configure do
  set :environment, (ENV["RACK_ENV"] || :development).to_sym
  set :server, :puma
  set :max_count, (ENV["MAX_COUNT"] || 100).to_i
  set :public_folder, File.expand_path("../public", __FILE__)
  enable :static

  Faker::Config.locale = "pt-BR"
end
```

*   `MAX_COUNT`: máximo de registros por requisição (default `100`).  
    Ajuste via env var: `MAX_COUNT=500 bundle exec rackup -p 9292`.

***

## Endpoints

### `GET /`

Retorna metadados da aplicação: segmentos suportados, parâmetros e limites.

### `GET /health`

Healthcheck simples:

```json
{ "status": "ok", "time": "2025-12-12T12:34:56Z" }
```

### `GET /generate`

Gera e retorna a massa de dados conforme parâmetros (abaixo).

***

## Parâmetros

*   `segment` (default: `pf`)
    *   `pf`, `pj`, `endereco`, `contato`,
    *   `produto`, `cliente`, `pedido`, `transacao`, `cartao`,
    *   `endereco_internacional` (aliases: `endereco_intl`, `intl`)
*   `count` (default: `1`, respeita `MAX_COUNT`)
*   `format` (`json` | `csv`, default `json`)
*   `locale` (default: `pt-BR`)
    *   Ex.: `en`, `es`, `fr`, `de`; controla idioma do Faker (endereços/cidades/nomes).
*   `seed` (opcional):
    *   Geração **determinística por requisição**; mesma seed e parâmetros → mesma saída.
*   `include` (opcional):
    *   **Whitelist** de campos; suporta **dot notation** para nested (ex.: `endereco.cep`).
*   `exclude` (opcional):
    *   Remove campos; suporta **dot notation**.

> Na UI, a aba **Avançado** também possui **filtro de campos (preview)** e **limite de exibição (preview)** — atuam apenas no front-end. `include/exclude` são **server-side** e afetam a resposta (JSON/CSV).

***

## Segmentos suportados

*   `pf` — Pessoa Física: nome, CPF (válido), email, telefone, endereço BR.
*   `pj` — Pessoa Jurídica: razão social, nome fantasia, CNPJ (válido), IE, contato, endereço BR.
*   `contato` — Nome, email, telefone.
*   `endereco` — Endereço BR.
*   `endereco_internacional` — Endereço internacional (campos: street, city, state, postal\_code, country).
*   `produto` — SKU, nome, categoria, preço, estoque.
*   `cliente` — PF + score crédito, limite, renda, perfil, status e preferências.
*   `pedido` — Itens (produto, quantidade, subtotais), total, status.
*   `transacao` — Para pedido (metodologia: cartão/pix/boleto), NSU, autorização, status. Se `cartao`, inclui dados mascarados do cartão.
*   `cartao` — PAN fictício (Luhn), bandeira, validade, CVV, nome portador. **PAN mascarado** e `pan_hash` fictício.

> **Nota**: Em `endereco` com `locale != pt-BR`, o servidor retorna automaticamente `endereco_internacional`.

***

## Seed determinística (por requisição)

*   Implementada com `Random.new(seed.to_i)` **por requisição**; `Faker::Config.random` recebe o RNG local.
*   **Nunca** usamos `srand` (global), e sempre **resetamos** o `Faker::Config.random` em `ensure` para evitar vazamento entre chamadas.

Padrão usado em `/generate`:

```ruby
begin
  @rng = seed ? Random.new(seed.to_i) : Random.new
  Faker::Config.random = @rng

  builder = segment_builder(segment)
  data = Array.new(count) { builder.call }

  # renderização...
ensure
  Faker::Config.random = nil
  @rng = nil
end
```

***

## Include/Exclude (server-side)

### `include=...`

Mantém **apenas** os campos listados. Suporta **dot notation**:

*   `include=nome,email,endereco.cep` → inclui `nome`, `email` e `{ endereco: { cep } }`.

### `exclude=...`

Remove campos listados; também suporta **dot notation**:

*   `exclude=endereco,telefone,endereco.cep`

> **Regra**: Se `include` for informado, `exclude` é ignorado (whitelist tem prioridade).

***

## Formato CSV

*   Cabeçalhos: união das chaves **top-level** de todos os registros gerados (para contemplar variações).
*   Valores **Hash/List** são **serializados em JSON** dentro da célula.
*   Separador padrão: `;`.

Exemplo de geração:

```ruby
def to_csv(array)
  headers = array.map(&:keys).flatten.uniq
  CSV.generate(col_sep: ";") do |csv|
    csv << headers
    array.each do |row|
      csv << headers.map { |h|
        row[h].is_a?(Hash) || row[h].is_a?(Array) ? JSON.generate(row[h]) : row[h]
      }
    end
  end
end
```

***

## Front-end (UI)

*   **Pasta**: `public/`
    *   `index.html`: layout premium com **tabs** **Simples** / **Avançado**.
    *   `styles.css`: dark/light theme, gradientes, glassmorphism, animações.
    *   `app.js`: chamadas à API, preview, skeleton, toasts, **limpeza ao trocar de aba**.
*   **Botão “Copiar JSON”**:
    *   Visível **somente** quando `format=json` **e** aba **Simples** ativa.
*   **Locale (placeholder)**:
    *   `placeholder="pt-BR (padrão) · en · es · fr"`, e se vazio o front envia `pt-BR`.

Servindo a UI:

*   O Sinatra serve `/public` automaticamente.
*   Acesse: `http://localhost:9292/index.html`.

> Se desejar servir a UI na raiz `/`, adicione:

```ruby
get "/" do
  content_type "text/html"
  send_file File.join(settings.public_folder, "index.html")
end
```

***

## Exemplos de uso (`curl`)

> Dica: instale `jq` para formatar JSON.

**PF (JSON)**

```bash
curl -s "http://localhost:9292/generate?segment=pf&count=3&format=json" | jq
```

**PF (JSON) com seed**

```bash
curl -s "http://localhost:9292/generate?segment=pf&count=3&format=json&seed=123" | jq
```

**Cliente (CSV)**

```bash
curl -s "http://localhost:9292/generate?segment=cliente&count=5&format=csv" > cliente.csv
```

**Pedido (JSON)**

```bash
curl -s "http://localhost:9292/generate?segment=pedido&count=2&format=json" | jq
```

**Cartão (JSON)**

```bash
curl -s "http://localhost:9292/generate?segment=cartao&count=3&format=json" | jq
```

**Transação (JSON)**

```bash
curl -s "http://localhost:9292/generate?segment=transacao&count=3&format=json" | jq
```

**Endereço Internacional (locale en)**

```bash
curl -s "http://localhost:9292/generate?segment=endereco_internacional&count=3&format=json&locale=en" | jq
```

**Include/Exclude**

```bash
# include top-level + nested:
curl -s "http://localhost:9292/generate?segment=pf&count=2&format=json&include=nome,email,endereco.cep" | jq

# exclude nested:
curl -s "http://localhost:9292/generate?segment=pf&count=2&format=json&exclude=endereco.cep,telefone" | jq
```

***

## Docker

**Dockerfile** básico:

```dockerfile
FROM ruby:3.3-alpine

RUN apk add --no-cache build-base

WORKDIR /app
COPY Gemfile Gemfile.lock* /app/
RUN bundle install

COPY . /app

ENV RACK_ENV=production
ENV PORT=9292
ENV MAX_COUNT=200

EXPOSE 9292
CMD ["bundle", "exec", "puma", "-p", "9292", "config.ru"]
```

Build & run:

```bash
docker build -t dataseed:latest .
docker run --rm -p 9292:9292 dataseed:latest
# Acesse: http://localhost:9292/index.html
```

***

## Puma (config opcional)

`config/puma.rb`:

```ruby
environment ENV.fetch("RACK_ENV", "development")
rackup File.expand_path("../config.ru", __dir__)
port ENV.fetch("PORT", 9292)

threads 0, 5
workers ENV.fetch("WEB_CONCURRENCY", 0)
preload_app!
```

Rodar:

```bash
bundle exec puma -C config/puma.rb
```

***

## Troubleshooting

### `ERROR: No application configured, nothing to run`

*   Rode `puma` fora do diretório do projeto ou sem `config.ru`.
*   Solução:
    ```bash
    bundle exec rackup -p 9292
    # ou
    bundle exec puma -p 9292 config.ru
    ```

### `cannot load such file -- cpf_cnpj`

*   O projeto não usa mais essa gem.
*   Remova `require "cpf_cnpj"` do `app.rb`.
*   Se quiser usar a gem, adicione ao `Gemfile` e rode `bundle install`.

### CSS não é carregado

*   Estrutura:
    public/index.html
    public/styles.css
    public/app.js
*   Em `app.rb`: `set :public_folder, ...` e `enable :static`.
*   No HTML: `/styles.css`.
*   Teste direto: `http://localhost:9292/styles.css` → deve retornar **200**.

### Seed afetando Simples

*   Corrigido: seed é **por requisição** e resetada em `ensure`.
*   Não usar `srand`.

### Botão “Copiar JSON” exibindo fora de hora

*   JS deve chamar `updateCopyVisibility()` ao:
    *   trocar **aba**,
    *   trocar **format**,
    *   **init** da página.
*   CSS deve ter `.hidden { display: none !important; }`.

***

## Boas práticas

*   **Limite `MAX_COUNT`** de acordo com seu ambiente.
*   **Logs e rate-limit** simples se expor publicamente.
*   **Sem dados reais** em QA/dev; todos são fictícios.
*   **Documente perfis customizados** e mapeie colunas CSV conforme consumo do time.
*   **Versione a API** se evoluir contratos (ex.: `/v1/generate`).

***

## Licença

Uso interno para testes de QA/Dev.  
Se tornar OSS, sugerimos **MIT License** com ressalva explícita de **dados fictícios**.

***

## Anexos (opcional)

### Servir a UI em `/`

```ruby
get "/" do
  content_type "text/html"
  send_file File.join(settings.public_folder, "index.html")
end
```

### Makefile (atalhos)

```makefile
run:
\tbundle exec rackup -p 9292

puma:
\tbundle exec puma -p 9292 config.ru

docker-build:
\tdocker build -t dataseed:latest .

docker-run:
\tdocker run --rm -p 9292:9292 dataseed:latest
```

### Postman Collection

*   Crie uma collection com:
    *   `GET /generate` (cada segmento, JSON/CSV)
    *   `GET /health`
    *   Exemplo com `seed`, `include`, `exclude`
*   Exporte para `postman_collection.json` no repositório.

***
