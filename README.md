# Scaffold — Angular

Aplicación Angular mínima que **cumple `PLATFORM.md`** y que se ha desplegado de
verdad en el namespace `local` del cluster (no es una plantilla teórica).

Generada con `@angular/cli@22.0.8` y modificada sólo en lo que exige el
contrato. Todo lo demás es Angular estándar.

## Qué se le ha añadido a un `ng new`

| Fichero | Por qué |
|---|---|
| `angular.json` → `serve.options` | `host: 0.0.0.0`, `port: 8080`, `allowedHosts: [".localtest.me"]`. Sin esto el dev server rechaza las peticiones que llegan por el ingress (`PLATFORM.md` §14.1). |
| `public/health` | `GET /health` → `200`. Lo usan las tres probes. |
| `public/config.json` | Configuración que ve el navegador. Una SPA **no** lee variables de entorno del contenedor (`PLATFORM.md` §5). |
| `Dockerfile` | Multietapa `deps` / **`dev`** / `build` / `prod`. |
| `deploy/nginx.conf` | Etapa `prod`: nginx en 8080, `/health` y fallback SPA. |
| `k8s/` | `base` + `overlays/{local,pre,pro}`. |
| `skaffold.yaml` | El bucle rápido de `local` (`PLATFORM.md` §15): qué se sincroniza, qué fuerza rebuild y qué puertos se reenvían. |

El puerto es **8080 en las dos etapas** (dev server y nginx) a propósito: así el
`containerPort` no cambia entre entornos.

## Instanciarlo

1. Copiar el directorio al repo del proyecto nuevo.
2. Renombrar `catalogo-web` por el nombre real de la app — **es obligatorio**: en el
   cluster único todos los proyectos comparten namespace y dos Services con el
   mismo nombre se pisan sin error visible (`PLATFORM.md` §10).

   ```bash
   grep -rl catalogo-web . --exclude-dir=node_modules | xargs sed -i 's/catalogo-web/<mi-app>/g'
   ```

   Afecta a `angular.json`, `package.json`, `k8s/**` y a la ruta
   `dist/catalogo-web/browser` del `Dockerfile`.
3. Reservar un rango de puertos en `PORTS.md` del repo de plataforma.

## Bucle rápido — la forma normal de trabajar

```bash
skaffold dev        # construye, despliega en `local`, y se queda vigilando
```

El primer arranque cuesta minutos (imagen + `npm ci` + primera compilación de
Angular). A partir de ahí, **guardar un `.ts` y ver el cambio cuesta ~2 s**
(medido: 1,85–2,40 s; `PLATFORM.md` §15). El pod **no** se reinicia: Skaffold
copia el fichero dentro y el dev server recompila en incremental.

- Se ve en `http://catalogo-web.local.localtest.me` — el HMR llega al navegador solo.
- `Ctrl-C` para. Por defecto **borra del cluster** lo que había desplegado.
- Reenvío de puertos: `localhost:19040` → el Service (rango de `PORTS.md`).
  Ojo: por ese puerto el HMR puede no conectar (§14.2); el ingress sí funciona.
- **Tocar `package.json` reconstruye la imagen** en vez de sincronizar. Es
  intencionado (§15): un pod con dependencias que nadie instaló es un estado que
  no corresponde a ninguna imagen.

Configuración: [`skaffold.yaml`](skaffold.yaml), comentado línea a línea.

## Ciclo corto, a mano (sin Skaffold — para diagnosticar)

```bash
APP=catalogo-web; SHA=$(git rev-parse --short=12 HEAD)
docker build --target dev -t registry.localtest.me:5111/$APP:$SHA .
docker push registry.localtest.me:5111/$APP:$SHA
kubectl kustomize k8s/overlays/local | sed "s#$APP:dev#$APP:$SHA#" | kubectl apply -f -
kubectl -n local rollout status deploy/$APP

curl -s http://$APP.local.localtest.me/health   # -> ok
```

## Producción

```bash
docker build --target prod -t registry.localtest.me:5111/$APP:$SHA .
```

En `pre`/`pro` no se aplica nada a mano: el tag lo escribe CI **en el repo de
este proyecto** —que es donde viven sus overlays— y ArgoCD reconcilia
(`PLATFORM.md` §2 y §11).

## Si algo falla

| Síntoma | Causa probable |
|---|---|
| 403 con HTML de "blocked request" | `allowedHosts` no cubre el host (§14.1) |
| Carga pero no recarga sola | Websocket de HMR; se ve en la **consola del navegador**, no en los logs del pod (§14.2) |
| El pod se reinicia al compilar | OOM. `kubectl -n local describe pod <pod> \| grep -A2 'Last State'` → `OOMKilled` (§8) |
| `connection refused` en las probes | El dev server escucha en `localhost` en vez de `0.0.0.0` (§3) |
| `ErrImagePull` con un nombre de imagen que no está en ningún fichero | El ConfigMap `kube-public/local-registry-hosting` anuncia `localhost:5111` y Skaffold lo usa de default-repo (§15, *el fallo que costó la tarde*). Lo corrige `up.sh`. |
| Guardar un `.ts` no hace nada | ¿Llegó el fichero? `kubectl -n local exec deploy/catalogo-web -- ls -l /app/src/app`. Si llegó y no recompila, entonces sí es el watcher (§15) |
