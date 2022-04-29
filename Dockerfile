  #---------------------#
 #    phoenix 1.6.6    #
#---------------------#

FROM elixir:1.13
MAINTAINER Manlio García <info@manliogarcia.es>

ARG USER_NAME=elixir
ARG GROUP_NAME=elixir
ARG USER_UID=40759
ARG USER_GID=40759
ARG LANGUAGE=en_US

ENV APP_DIRECTORY=app
ENV APP_NAME=app
ENV DOMAIN=localhost
ENV PORT=4000
ENV MIX_ENV=dev

EXPOSE $PORT

# Install dependencies
RUN apt-get update  \
 && apt-get install \
 sudo               \
 locales            \
 apt-utils          \
 build-essential    \
 inotify-tools      \
 git                \
 postgresql-client  \
 libcap2-bin        \
 -y \
 && apt autoremove --purge -y \
 && rm -rf /var/cache/apt /var/lib/apt/lists

# Add custom files
RUN echo '\
#!/bin/bash\n\
cd ~/"$APP_DIRECTORY" \\\n\
&& iex --name "$(date -u +%Y%m%d%H%M%S)@${DOMAIN:-${HOSTNAME:-localhost}}" --cookie "${ERLANG_COOKIE:-app}" --remsh "app@${DOMAIN:-${HOSTNAME:-localhost}}"\n\
'>/usr/local/bin/attach \
  && chmod +x /usr/local/bin/attach \
  && echo '\
#!/bin/bash\n\
echo "sanitizing..."\n\
chown -R '$USER_NAME':'$USER_GROUP' /home/'$USER_NAME'/"$APP_DIRECTORY"\n\
if [ -f /bootstrap ]; then\n\
  echo "bootstraping..."\n\
  chmod +x /bootstrap\n\
  . /bootstrap\n\
fi\n\
echo "done."\n\
'>/usr/local/bin/sanitize \
 && chmod +x /usr/local/bin/sanitize \
  && echo '\
#!/bin/bash\n\
cd /home/'$USER_NAME'/"$APP_DIRECTORY" && mix phx.gen.secret ${0:-128}\n\
'>/usr/local/bin/create_secret \
 && chmod +x /usr/local/bin/create_secret \
 && echo $USER_NAME ' ALL=(ALL) NOPASSWD:SETENV: /usr/local/bin/sanitize'>/etc/sudoers.d/sudoers \
 && chmod 0440 /etc/sudoers.d/sudoers

# Set the locale
RUN touch /usr/share/locale/locale.alias
RUN sed -i -e 's/# '${LANGUAGE}'.UTF-8 UTF-8/'${LANGUAGE}'.UTF-8 UTF-8/' /etc/locale.gen \
  && locale-gen

## Enable low ports for erlang
RUN setcap 'cap_net_bind_service=+ep' /usr/local/lib/erlang/erts-*/bin/erlexec
# Enable low ports for beam
RUN setcap 'cap_net_bind_service=+ep' /usr/local/lib/erlang/erts-*/bin/beam.smp

# Add non-root user
RUN groupadd -g "$USER_GID" "$GROUP_NAME" \
  && useradd -s /bin/bash -u "$USER_UID" -g "$USER_GID" -m "$USER_NAME"

# Initialize elixir environment
RUN sudo -u elixir bash -c "\
  mix local.hex --force; \
  mix local.rebar --force; \
  mix archive.install --force hex phx_new 1.6.6;"

WORKDIR /home/$USER_NAME/$APP_DIRECTORY
USER $USER_NAME

CMD bash -c '\
  sudo sanitize; \
  [ ! -d ~/"$APP_DIRECTORY/.git" ] && [ "$GIT_REPO" != "" ] \
  && git clone --recursive "$GIT_REPO" ~/"$APP_DIRECTORY";\
  [ ! -f ~/"$APP_DIRECTORY/mix.exs" ] \
  && shopt -s dotglob \
  && mix phx.new --app "$APP_NAME" ~/"$APP_DIRECTORY/tmp" \
  && sed -i "51s/$/,\n      {:credo, \"~> 1.6\", only: [:dev, :test], runtime: false}/g" \
       ~/"$APP_DIRECTORY/tmp/mix.ex" \
  && mv ~/"$APP_DIRECTORY/tmp"/* ~/"$APP_DIRECTORY/." \
  && rmdir ~/"$APP_DIRECTORY/tmp";\
  cd ~/"$APP_DIRECTORY" \
  && mix deps.get \
  && exec elixir \
  --name "${ERLANG_NAME:-app}@${DOMAIN:-${HOSTNAME:-localhost}}" \
  --cookie "${ERLANG_COOKIE:-app}" \
  -S mix phx.server;'
