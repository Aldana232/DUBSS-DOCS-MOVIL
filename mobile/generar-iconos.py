"""
Genera los iconos y la pantalla de inicio de la app Android a partir del escudo de la DUBSS
(mobile/assets/escudo-512.png, copia del escudo del sistema). Se ejecuta una vez (o cuando cambie el escudo):  python generar-iconos.py
Requiere Pillow.
"""
from pathlib import Path

from PIL import Image

RAIZ = Path(__file__).resolve().parent
ESCUDO = Image.open(RAIZ / "assets" / "escudo-512.png").convert("RGBA")
RES = RAIZ / "android" / "app" / "src" / "main" / "res"
FONDO = (23, 26, 35, 255)          # #171a23, el color de la barra del sistema

# Icono clásico (cuadrado de cada densidad) y capa frontal del icono adaptable (108 dp).
DENSIDADES = {"mdpi": (48, 108), "hdpi": (72, 162), "xhdpi": (96, 216), "xxhdpi": (144, 324), "xxxhdpi": (192, 432)}

for nombre, (lado, adaptable) in DENSIDADES.items():
    carpeta = RES / f"mipmap-{nombre}"
    clasico = ESCUDO.resize((lado, lado), Image.LANCZOS)
    clasico.save(carpeta / "ic_launcher.png")
    clasico.save(carpeta / "ic_launcher_round.png")
    # El sistema recorta el icono adaptable: el escudo ocupa el 62 % central para que nunca quede cortado.
    capa = Image.new("RGBA", (adaptable, adaptable), (0, 0, 0, 0))
    medida = int(adaptable * 0.62)
    capa.paste(ESCUDO.resize((medida, medida), Image.LANCZOS), ((adaptable - medida) // 2,) * 2)
    capa.save(carpeta / "ic_launcher_foreground.png")

(RES / "values" / "ic_launcher_background.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#171A23</color>\n</resources>\n',
    encoding="utf-8",
)

# Pantalla de inicio: fondo oscuro con el escudo al centro, del mismo tamaño que las que trae Capacitor.
cuenta = 0
for archivo in RES.glob("drawable*/splash.png"):
    ancho, alto = Image.open(archivo).size
    lienzo = Image.new("RGBA", (ancho, alto), FONDO)
    lado = int(min(ancho, alto) * 0.34)
    lienzo.paste(ESCUDO.resize((lado, lado), Image.LANCZOS), ((ancho - lado) // 2, (alto - lado) // 2), ESCUDO.resize((lado, lado), Image.LANCZOS))
    lienzo.convert("RGB").save(archivo)
    cuenta += 1
print(f"Iconos generados en {len(DENSIDADES)} densidades y {cuenta} pantallas de inicio.")
