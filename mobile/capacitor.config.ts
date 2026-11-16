import type { CapacitorConfig } from "@capacitor/cli";

/**
 * La app Android no empaqueta el sistema: abre el sitio de la DUBSS dentro de un WebView nativo y le suma lo que
 * un navegador no puede dar (notificaciones push con la app cerrada, icono, pantalla de inicio, botón «atrás»).
 * Así, cada mejora del sistema llega a todos los celulares sin volver a publicar el APK.
 *
 * La dirección se fija al compilar:  DUBSS_URL=https://sistema.ejemplo.bo  (o  .\build-apk.ps1 -Url ...)
 *   · Producción: https y un dominio. Es lo recomendado (activa el modo sin conexión completo de la planilla).
 *   · Pruebas:    http://IP-DE-LA-PC:3000  (misma red Wi-Fi)  o  http://localhost:3000 con «adb reverse».
 */
const url = (process.env.DUBSS_URL || "http://10.0.2.2:3000").replace(/\/+$/, "");   // 10.0.2.2 = la PC vista desde el emulador
const inicio = process.env.DUBSS_INICIO || "/planilla";                              // se redirige al login si no hay sesión

const config: CapacitorConfig = {
  appId: "bo.edu.uagrm.dubss",
  appName: "DUBSS",
  webDir: "www-build",              // copia de www/ con la dirección del sistema ya puesta (la genera build-apk.ps1)
  backgroundColor: "#171a23",
  server: {
    url: url + inicio,
    cleartext: url.startsWith("http://"),
    errorPath: "offline.html",                       // pantalla local si el servidor no responde
    allowNavigation: [new URL(url).host],            // la app solo navega dentro del sistema
  },
  android: {
    allowMixedContent: false,
    // «DUBSSPush» le avisa al sistema que este APK trae Firebase y puede registrar el celular para notificaciones push.
    appendUserAgent: "DUBSSApp/1.0" + (process.env.DUBSS_PUSH === "1" ? " DUBSSPush" : ""),
    webContentsDebuggingEnabled: process.env.DUBSS_DEBUG === "1",
  },
  plugins: {
    SplashScreen: { launchShowDuration: 1200, backgroundColor: "#171a23", showSpinner: false },
    StatusBar: { style: "DARK", backgroundColor: "#171a23" },
    PushNotifications: { presentationOptions: ["badge", "sound", "alert"] },
  },
};

export default config;
