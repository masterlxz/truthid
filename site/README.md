# TruthID — Site

Site do TruthID: conta (`Customer`) e, no futuro, billing pro tier pago opt-in (ver
`../project/ROADMAP.md`, seção "Migração de storage + Tier facilitado"). Este v1 é só o
esqueleto — login via Google OAuth criando um `Customer` de verdade. Sem billing, sem bootstrap
de identidade TruthID ainda.

- `backend/` — Ruby on Rails (API-only), OmniAuth como fonte de verdade do login.
- `frontend/` — Next.js (App Router, TypeScript, Tailwind).
- Postgres via Docker Compose — nada disso precisa de Ruby/Node/Postgres instalado no host.

## Rodando

1. Crie um OAuth Client ID no [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
   (tipo "Web application"), com redirect URI `http://localhost:3001/auth/google_oauth2/callback`.
2. `cp .env.example .env` (neste diretório) e preencha `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET`
   com os valores reais do passo 1.
3. `docker compose up --build`
4. Frontend em [http://localhost:3000](http://localhost:3000), backend em
   `http://localhost:3001` (health check em `/up`).

Sem preencher o `.env` com credenciais reais, tudo sobe normalmente — só o botão "Entrar com
Google" não vai completar o login (o Google rejeita um client id vazio).

## Testes

```sh
docker compose run --rm backend bin/rails test
```

## Modelagem

- `Customer` — a conta (email, nome, avatar). É a entidade que vai virar `customer_id` do
  Stripe/Mercado Pago quando o billing for implementado.
- `Identity` — um vínculo `(provider, uid)` por login social, `belongs_to :customer`. Um
  `Customer` pode ter várias `Identity` (Google hoje; GitHub e o próprio TruthID como provider
  são extensões futuras — a modelagem já suporta, só faltam as strategies do OmniAuth).

## Simplificação deliberada do v1

O link "Entrar com Google" do frontend é uma navegação de página inteira (`<a href>`) direto pra
`/auth/google_oauth2`, sem passar pelo `omniauth-rails_csrf_protection` (que exigiria um form
POST com token CSRF, mais complicado de coordenar entre o Rails e um frontend em outra origem).
Mitigado com `OmniAuth.config.allowed_request_methods = [:get, :post]` — aceita o risco baixo de
login CSRF por enquanto (`Customer` ainda não carrega billing nem dado sensível). Revisitar antes
de qualquer billing real entrar em produção.

## Fora de escopo deste v1

- Billing (Stripe/Mercado Pago), Entitlement Service, bootstrap de identidade TruthID.
- GitHub/TruthID como provider adicional de login.
- Migração da documentação (`../docs/`, Docusaurus) pra cá — decidida, mas "aos poucos", não faz
  parte deste v1.
