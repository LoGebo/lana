# Notas alimentos_mx.json

Fuente unica: USDA FoodData Central, dataset SR Legacy (descarga oficial https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip). Cada fila cita el fdcId y el nombre exacto del alimento USDA. Macros = valor USDA por 100 g x gramos de la porcion.

## Limitaciones (leer)
- NO se uso SMAE, tablas INCMNSZ ni etiquetas de marcas mexicanas (Bimbo, Lala, Sabritas, etc.): no se pudo extraer datos confiables en esta sesion. Sin datos oficiales, no se incluyeron marcas ni cadenas (OXXO, HEB, etc.).
- Los gramos por porcion son estimaciones tipicas mias (no verificadas contra SMAE); revisar los de pan, tortilla, tamal, platillos.
- Aproximado=true: sustituto USDA de un alimento mexicano (queso Oaxaca = mozzarella entero, manchego = cheddar, queso fresco USDA, bolillo = hard roll, concha = pan dulce, carnitas = paleta estofada, chile poblano = pimiento verde, crema = sour cream) o platillo variable (tamal, quesadilla, burrito, hamburguesa, pizza: datos USDA de restaurantes/cadenas EUA).
- kcal_cuadra=false (regla 4P+4C+9G +-10%): alimentos con mucha fibra/agua (verduras, frutas), alcohol (cerveza, tequila, vino) y elote/tofu. Son diferencias esperadas por factores Atwater y fibra, no errores; ver campo nota.
- Tequila: dato USDA de destilado 80 proof (40% alc.), 1 caballito 42 g.

## Omitidos por falta de dato confiable
Taco al pastor/bistec/carnitas, torta, sope, chilaquiles, pozole, birria, caldo de res, tostada preparada, esquite, atole, churro, queso panela, pan tostado, cereales de marca, barras proteicas, sopas instantaneas Maruchan, cafe con leche, refrescos/jugos de marca mexicana, comida de cadenas.
