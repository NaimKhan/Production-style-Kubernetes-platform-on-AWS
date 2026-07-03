FROM nginx:1.27-alpine

# Default values, overridable at runtime (docker-compose env or K8s env)
ENV BACKEND_HOST=backend \
    BACKEND_PORT=8080

# Official nginx image auto-renders any *.template file in this
# directory via envsubst on container start, into /etc/nginx/conf.d/
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY public/ /usr/share/nginx/html/

RUN chown -R nginx:nginx /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1/healthz || exit 1
