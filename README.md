# Hygeia

## Development

To start your Phoenix server:

* [Install `wkhtmltopdf`](https://github.com/gutschilla/elixir-pdf-generator#wkhtmltopdf)
* Install `poppler-utils` (`brew install poppler`, `apt-get install poppler-utils`, `apk add poppler-utils`)
* Install Elixir / Node / Erlang using [`asdf`](https://asdf-vm.com/) as specified in `.tool-versions`
* Start Database

```console
$ docker volume create postgres
$ docker run \
    --restart always \
    --name postgres \
    -v postgres:/var/lib/postgresql/data \
    -p 5432:5432 \
    -d \
    -e POSTGRES_PASSWORD="" \
    -e POSTGRES_USER="root" \
    -e POSTGRES_HOST_AUTH_METHOD="trust" \
    postgres:latest
```

  * Install dependencies with `mix deps.get`
  * Crete Local `.env` file
  * Load Local `.env` file
    - For `zsh` users I recommend https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/dotenv
    - Using ``npx dotenv-cli `ps -o fname --no-headers $$`` you can load all env variables into a new shell instead
  * Create and migrate your database with `mix ecto.setup` inside the `apps/hygeia` directory
  * Install Node.js dependencies with `npm install` inside the `apps/hygeia_web/assets` directory
  * Start Phoenix endpoint with `mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Environment Variables

See [`.env.example`](./.env.example)