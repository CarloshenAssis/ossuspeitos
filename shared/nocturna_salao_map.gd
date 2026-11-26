extends RefCounted
## Greybox do Salão Central, da Biblioteca, da Cozinha, da Sala de Jantar, do Quarto de Hóspedes, do Lavabo, do Banheiro de Mármore e do Jardim de Inverno. Todas as coordenadas de piso estão em XZ.

const CELL := MansionMap.CELL
const WALL_TOP := 7.0 + MansionMap.SLAB_THICKNESS
const MIN_X := -10.5
const GALLERY_FLOOR := 3.5
const GALLERY := {"id": "galeria", "name": "Galeria", "kind": "room", "min": Vector2(0, 0), "max": Vector2(16, 2), "floor": GALLERY_FLOOR, "ceiling": 7.0, "space": "salao", "y": GALLERY_FLOOR}
const SPACES := [
	{"id": "salao", "name": "Salão Central", "kind": "room", "min": Vector2(0, 0), "max": Vector2(16, 14), "ceiling": 7.0},
	{"id": "biblioteca", "name": "Biblioteca", "kind": "room", "min": Vector2(MIN_X, 5), "max": Vector2(-0.5, 14), "ceiling": 3.5},
	{"id": "hospedes", "name": "Quarto de Hóspedes", "kind": "room", "min": Vector2(MIN_X, 14.5), "max": Vector2(-4.5, 19.5), "ceiling": 3.5},
	{"id": "lavabo", "name": "Lavabo", "kind": "corridor", "min": Vector2(-4, 16), "max": Vector2(5, 19.5), "ceiling": 3.5},
	{"id": "banheiro_marmore", "name": "Banheiro de Mármore", "kind": "room", "min": Vector2(-4, 20), "max": Vector2(5, 26), "ceiling": 3.5},
	{"id": "jardim_acesso", "name": "Acesso ao Jardim de Inverno", "kind": "corridor", "min": Vector2(-4, 26.5), "max": Vector2(5, 29), "ceiling": 4.0},
	{"id": "cozinha", "name": "Cozinha", "kind": "room", "min": Vector2(16.5, 5), "max": Vector2(26.5, 14), "ceiling": 3.5},
	{"id": "jantar", "name": "Sala de Jantar", "kind": "room", "min": Vector2(5.5, 14.5), "max": Vector2(19.5, 22.5), "ceiling": 3.5},
	{"id": "jardim_inverno", "name": "Jardim de Inverno", "kind": "room", "min": Vector2(5.5, 23), "max": Vector2(19.5, 29), "ceiling": 4.0},
	# A extensão da asa leste dá largura útil à curva para a porta.
	GALLERY,
	{"id": "galeria_oeste", "name": "Galeria", "kind": "room", "min": Vector2(0, 2), "max": Vector2(4, 5), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "galeria_vao", "name": "Galeria", "kind": "room", "min": Vector2(6, 2), "max": Vector2(10, 5), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "galeria_leste", "name": "Galeria", "kind": "room", "min": Vector2(12, 2), "max": Vector2(16, 5), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "galeria_acesso", "name": "Galeria", "kind": "room", "min": Vector2(14.5, 5), "max": Vector2(16, 7), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "corredor_oeste", "name": "Corredor Superior", "kind": "corridor", "min": Vector2(16.5, 5), "max": Vector2(18, 10), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "corredor_leste", "name": "Corredor Superior", "kind": "corridor", "min": Vector2(18, 7), "max": Vector2(26.5, 10), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "patamar_servico", "name": "Patamar de Serviço", "kind": "corridor", "min": Vector2(24.5, 5), "max": Vector2(26.5, 7), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "quarto_norte", "name": "Quarto Norte", "kind": "room", "min": Vector2(MIN_X, 0), "max": Vector2(-0.5, 3), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "suite", "name": "Suíte", "kind": "room", "min": Vector2(MIN_X, 3.5), "max": Vector2(-0.5, 10), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "observatorio", "name": "Observatório", "kind": "room", "min": Vector2(27, 5), "max": Vector2(34, 8), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "musica", "name": "Sala de Música", "kind": "room", "min": Vector2(27, 8.5), "max": Vector2(34, 14), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "musica_acesso", "name": "Sala de Música", "kind": "room", "min": Vector2(27, 8), "max": Vector2(29, 8.5), "floor": GALLERY_FLOOR, "ceiling": 7.0},
]
const DOORS := [
	{"id": "porta_biblioteca", "room": "salao", "corridor": "biblioteca", "min": Vector2(-0.5, 7), "max": Vector2(0, 9)},
	{"id": "porta_hospedes", "room": "biblioteca", "corridor": "hospedes", "min": Vector2(-9.5, 14), "max": Vector2(-7.5, 14.5)},
	{"id": "porta_lavabo", "room": "hospedes", "corridor": "lavabo", "min": Vector2(-4.5, 16.5), "max": Vector2(-4, 18.5)},
	{"id": "porta_lavabo_jantar", "room": "lavabo", "corridor": "jantar", "min": Vector2(5, 16.5), "max": Vector2(5.5, 18.5)},
	{"id": "porta_banheiro_marmore", "room": "lavabo", "corridor": "banheiro_marmore", "min": Vector2(0.5, 19.5), "max": Vector2(2.5, 20)},
	{"id": "porta_jardim_inverno", "room": "banheiro_marmore", "corridor": "jardim_acesso", "min": Vector2(0.5, 26), "max": Vector2(2.5, 26.5)},
	{"id": "porta_cozinha", "room": "salao", "corridor": "cozinha", "min": Vector2(16, 7), "max": Vector2(16.5, 9)},
	{"id": "porta_jantar", "room": "salao", "corridor": "jantar", "min": Vector2(7, 14), "max": Vector2(9, 14.5)},
	{"id": "porta_cozinha_jantar", "room": "cozinha", "corridor": "jantar", "min": Vector2(16.5, 14), "max": Vector2(18.5, 14.5)},
	{"id": "porta_jardim_acesso", "room": "jardim_inverno", "corridor": "jardim_acesso", "min": Vector2(5, 26.5), "max": Vector2(5.5, 28.5)},
	{"id": "porta_jardim_jantar", "room": "jantar", "corridor": "jardim_inverno", "min": Vector2(11.5, 22.5), "max": Vector2(13.5, 23)},
	{"id": "porta_galeria_corredor", "room": "galeria_leste", "corridor": "corredor_oeste", "min": Vector2(16, 5), "max": Vector2(16.5, 7), "floor": GALLERY_FLOOR},
	{"id": "porta_quarto_norte", "room": "quarto_norte", "corridor": "galeria", "min": Vector2(-0.5, 0), "max": Vector2(0, 2), "floor": GALLERY_FLOOR},
	{"id": "porta_suite", "room": "suite", "corridor": "galeria_oeste", "min": Vector2(-0.5, 3), "max": Vector2(0, 5), "floor": GALLERY_FLOOR},
	{"id": "porta_observatorio", "room": "observatorio", "corridor": "patamar_servico", "min": Vector2(26.5, 5), "max": Vector2(27, 7), "floor": GALLERY_FLOOR},
	{"id": "porta_musica", "room": "musica", "corridor": "corredor_leste", "min": Vector2(26.5, 8), "max": Vector2(27, 10), "floor": GALLERY_FLOOR},
	{"id": "porta_suite_norte", "room": "suite", "corridor": "quarto_norte", "min": Vector2(-8, 3), "max": Vector2(-6, 3.5), "floor": GALLERY_FLOOR},
	{"id": "porta_musica_observatorio", "room": "musica", "corridor": "observatorio", "min": Vector2(29, 8), "max": Vector2(31, 8.5), "floor": GALLERY_FLOOR},
]
const FURNITURE := [
	{"id": "coluna_no", "min": Vector2(3, 6), "max": Vector2(4, 7), "height": 7.0},
	{"id": "coluna_ne", "min": Vector2(12, 6), "max": Vector2(13, 7), "height": 7.0},
	{"id": "coluna_so", "min": Vector2(3, 10), "max": Vector2(4, 11), "height": 7.0},
	{"id": "coluna_se", "min": Vector2(12, 10), "max": Vector2(13, 11), "height": 7.0},
	{"id": "estante_o", "space": "biblioteca", "min": Vector2(-10.5, 5), "max": Vector2(-9.5, 11.5), "height": 2.5},
	{"id": "estante_m", "space": "biblioteca", "min": Vector2(-7.5, 5), "max": Vector2(-6.5, 12), "height": 2.5},
	{"id": "estante_l", "space": "biblioteca", "min": Vector2(-4.5, 5), "max": Vector2(-3.5, 11.5), "height": 2.5},
	{"id": "ilha", "space": "cozinha", "min": Vector2(19.5, 10.5), "max": Vector2(23, 12.5), "height": 2.0},
	{"id": "mesa_jantar", "space": "jantar", "min": Vector2(9, 19.5), "max": Vector2(16, 21), "height": 1.0},
	{"id": "aparador", "space": "jantar", "min": Vector2(18.5, 16.5), "max": Vector2(19.5, 21.5), "height": 2.0},
	{"id": "cama", "space": "hospedes", "min": Vector2(-10.5, 16.5), "max": Vector2(-8.5, 18.5), "height": 1.0},
	{"id": "guarda_roupa", "space": "hospedes", "min": Vector2(-5.5, 14.5), "max": Vector2(-4.5, 16.5), "height": 2.5},
	{"id": "pia", "space": "lavabo", "min": Vector2(-3, 18.5), "max": Vector2(-1, 19.5), "height": 1.0},
	{"id": "banheira", "space": "banheiro_marmore", "min": Vector2(-4, 21.5), "max": Vector2(-1.5, 24), "height": 1.0},
	{"id": "divisoria", "space": "banheiro_marmore", "min": Vector2(3, 21), "max": Vector2(3.5, 24.5), "height": 2.5},
	{"id": "jardineira_o", "space": "jardim_inverno", "min": Vector2(5.5, 23.5), "max": Vector2(6.5, 26), "height": 1.0},
	{"id": "jardineira_s", "space": "jardim_inverno", "min": Vector2(8, 28), "max": Vector2(16, 29), "height": 1.0},
	{"id": "planta_a", "space": "jardim_inverno", "min": Vector2(8.5, 25), "max": Vector2(9.5, 26), "height": 2.5},
	{"id": "planta_b", "space": "jardim_inverno", "min": Vector2(15.5, 25), "max": Vector2(16.5, 26), "height": 2.5},
	{"id": "cama_norte", "space": "quarto_norte", "min": Vector2(MIN_X, 0.5), "max": Vector2(-8, 2.5), "height": 1.0, "floor": GALLERY_FLOOR},
	{"id": "guarda_norte", "space": "quarto_norte", "min": Vector2(MIN_X, 0), "max": Vector2(-9.5, 1.5), "height": 2.5, "floor": GALLERY_FLOOR},
	{"id": "cama_suite", "space": "suite", "min": Vector2(MIN_X, 6), "max": Vector2(-8, 9), "height": 1.0, "floor": GALLERY_FLOOR},
	{"id": "guarda_suite", "space": "suite", "min": Vector2(-1.5, 7), "max": Vector2(-0.5, 9.5), "height": 2.5, "floor": GALLERY_FLOOR},
	{"id": "pedestal_observatorio", "space": "observatorio", "min": Vector2(32, 6), "max": Vector2(33, 7), "height": 2.5, "floor": GALLERY_FLOOR},
	{"id": "piano", "space": "musica", "min": Vector2(28, 11.75), "max": Vector2(32, 13.75), "height": 1.0, "floor": GALLERY_FLOOR},
	{"id": "armario_musica", "space": "musica", "min": Vector2(33, 9), "max": Vector2(34, 12), "height": 2.5, "floor": GALLERY_FLOOR},
	# Decoração sólida apresentada no cliente: caixas AABB no mapa compartilhado.
	{"id": "sofa_salao_o", "min": Vector2(0.0, 10.934), "max": Vector2(1.250, 13.666), "height": 1.118, "space": "salao"},
	{"id": "sofa_salao_l", "min": Vector2(4.537, 10.934), "max": Vector2(5.463, 13.666), "height": 1.118, "space": "salao"},
	{"id": "mesa_centro_salao", "min": Vector2(2.380, 11.580), "max": Vector2(3.820, 13.020), "height": 0.557, "space": "salao"},
	{"id": "cadeira_salao", "min": Vector2(2.873, 10.870), "max": Vector2(3.328, 11.370), "height": 0.920, "space": "salao"},
	{"id": "comoda_salao", "min": Vector2(2.499, 13.260), "max": Vector2(3.701, 13.840), "height": 1.212, "space": "salao"},
	{"id": "carrinho_salao", "min": Vector2(12.916, 11.163), "max": Vector2(15.084, 12.237), "height": 1.718, "space": "salao"},
	{"id": "gaveteiro_salao", "min": Vector2(14.747, 9.992), "max": Vector2(15.753, 11.708), "height": 1.091, "space": "salao"},
	{"id": "vaso_salao_0", "min": Vector2(1.772, 13.199), "max": Vector2(2.428, 13.701), "height": 0.372, "space": "salao"},
	{"id": "vaso_salao_1", "min": Vector2(3.822, 13.199), "max": Vector2(4.478, 13.701), "height": 0.372, "space": "salao"},
	{"id": "vaso_salao_2", "min": Vector2(12.972, 11.249), "max": Vector2(13.628, 11.751), "height": 0.372, "space": "salao"},
	{"id": "vaso_salao_3", "min": Vector2(2.222, 3.949), "max": Vector2(2.878, 4.451), "height": 0.372, "space": "salao"},
	{"id": "vaso_salao_4", "min": Vector2(13.372, 5.149), "max": Vector2(14.028, 5.651), "height": 0.372, "space": "salao"},
	{"id": "vaso_salao_5", "min": Vector2(2.372, 10.199), "max": Vector2(3.028, 10.701), "height": 0.372, "space": "salao"},
	{"id": "escrivaninha_biblioteca", "min": Vector2(-3.200, 11.850), "max": Vector2(-2.000, 12.550), "height": 0.750, "space": "biblioteca"},
	{"id": "cadeira_biblioteca", "min": Vector2(-2.828, 11.050), "max": Vector2(-2.373, 11.550), "height": 0.920, "space": "biblioteca"},
	{"id": "gaveteiro_biblioteca", "min": Vector2(-9.658, 5.197), "max": Vector2(-7.942, 6.203), "height": 1.091, "space": "biblioteca"},
	{"id": "vaso_biblioteca_0", "min": Vector2(-1.278, 5.899), "max": Vector2(-0.622, 6.401), "height": 0.372, "space": "biblioteca"},
	{"id": "vaso_biblioteca_1", "min": Vector2(-10.478, 13.499), "max": Vector2(-9.822, 14.001), "height": 0.372, "space": "biblioteca"},
	{"id": "armario_cozinha_leste_0", "min": Vector2(25.870, 7.900), "max": Vector2(26.470, 8.400), "height": 0.880, "space": "cozinha"},
	{"id": "armario_cozinha_leste_1", "min": Vector2(25.870, 10.000), "max": Vector2(26.470, 10.500), "height": 0.880, "space": "cozinha"},
	{"id": "armario_cozinha_leste_2", "min": Vector2(25.870, 10.650), "max": Vector2(26.470, 11.150), "height": 0.880, "space": "cozinha"},
	{"id": "armario_cozinha_leste_3", "min": Vector2(25.870, 11.300), "max": Vector2(26.470, 11.800), "height": 0.880, "space": "cozinha"},
	{"id": "armario_cozinha_leste_4", "min": Vector2(25.870, 11.950), "max": Vector2(26.470, 12.450), "height": 0.880, "space": "cozinha"},
	{"id": "prateleira_cozinha", "min": Vector2(16.500, 10.574), "max": Vector2(17.000, 12.926), "height": 2.312, "space": "cozinha"},
	{"id": "maquina_cozinha", "min": Vector2(25.725, 13.000), "max": Vector2(26.475, 13.700), "height": 0.950, "space": "cozinha"},
	{"id": "carrinho_cozinha", "min": Vector2(23.613, 11.316), "max": Vector2(24.687, 13.484), "height": 1.718, "space": "cozinha"},
	{"id": "armario_cozinha_sul_0", "min": Vector2(20.750, 12.500), "max": Vector2(22.750, 14.000), "height": 0.880, "space": "cozinha"},
	{"id": "armario_cozinha_sul_1", "min": Vector2(22.250, 13.300), "max": Vector2(22.750, 13.900), "height": 0.880, "space": "cozinha"},
	{"id": "vaso_cozinha_0", "min": Vector2(19.872, 13.299), "max": Vector2(20.528, 13.801), "height": 0.372, "space": "cozinha"},
	{"id": "vaso_cozinha_1", "min": Vector2(23.272, 13.299), "max": Vector2(23.928, 13.801), "height": 0.372, "space": "cozinha"},
	{"id": "criado_hospedes", "min": Vector2(-9.175, 16.425), "max": Vector2(-8.625, 16.875), "height": 0.720, "space": "hospedes"},
	{"id": "cadeira_hospedes", "min": Vector2(-6.750, 16.573), "max": Vector2(-6.250, 17.027), "height": 0.920, "space": "hospedes"},
	{"id": "vaso_hospedes", "min": Vector2(-10.478, 18.899), "max": Vector2(-9.822, 19.401), "height": 0.372, "space": "hospedes"},
	{"id": "armario_lavabo", "min": Vector2(3.450, 16.150), "max": Vector2(3.950, 16.750), "height": 0.880, "space": "lavabo"},
	{"id": "vaso_lavabo", "min": Vector2(4.172, 16.199), "max": Vector2(4.828, 16.701), "height": 0.372, "space": "lavabo"},
	{"id": "vaso_sanitario", "min": Vector2(4.237, 21.000), "max": Vector2(5.000, 23.025), "height": 0.760, "space": "banheiro_marmore"},
	{"id": "armario_banheiro", "min": Vector2(4.400, 20.000), "max": Vector2(5.000, 20.800), "height": 0.880, "space": "banheiro_marmore"},
	{"id": "vaso_banheiro_0", "min": Vector2(-3.928, 20.299), "max": Vector2(-3.272, 20.801), "height": 0.372, "space": "banheiro_marmore"},
	{"id": "vaso_banheiro_1", "min": Vector2(4.372, 25.499), "max": Vector2(5.000, 26.000), "height": 0.372, "space": "banheiro_marmore"},
	{"id": "vaso_banheiro_2", "min": Vector2(-4.028, 24.099), "max": Vector2(-3.372, 24.601), "height": 0.372, "space": "banheiro_marmore"},
	{"id": "sofa_jantar", "min": Vector2(7.784, 21.577), "max": Vector2(10.516, 22.503), "height": 1.118, "space": "jantar"},
	{"id": "cadeira_jantar_canto", "min": Vector2(6.150, 16.073), "max": Vector2(6.650, 16.527), "height": 0.920, "space": "jantar"},
	{"id": "vaso_jantar_0", "min": Vector2(6.022, 14.749), "max": Vector2(6.678, 15.251), "height": 0.372, "space": "jantar"},
	{"id": "cadeira_mesa_n_0", "min": Vector2(9.942, 19.210), "max": Vector2(10.392, 19.590), "height": 0.900, "space": "jantar"},
	{"id": "cadeira_mesa_s_0", "min": Vector2(9.942, 20.910), "max": Vector2(10.392, 21.290), "height": 0.900, "space": "jantar"},
	{"id": "cadeira_mesa_n_1", "min": Vector2(12.275, 19.210), "max": Vector2(12.725, 19.590), "height": 0.900, "space": "jantar"},
	{"id": "cadeira_mesa_s_1", "min": Vector2(12.275, 20.910), "max": Vector2(12.725, 21.290), "height": 0.900, "space": "jantar"},
	{"id": "cadeira_mesa_n_2", "min": Vector2(14.608, 19.210), "max": Vector2(15.058, 19.590), "height": 0.900, "space": "jantar"},
	{"id": "cadeira_mesa_s_2", "min": Vector2(14.608, 20.910), "max": Vector2(15.058, 21.290), "height": 0.900, "space": "jantar"},
	{"id": "cadeira_mesa_o", "min": Vector2(8.675, 20.060), "max": Vector2(9.125, 20.440), "height": 0.900, "space": "jantar"},
	{"id": "cadeira_mesa_l", "min": Vector2(15.875, 20.060), "max": Vector2(16.325, 20.440), "height": 0.900, "space": "jantar"},
	{"id": "arvore_jardim_0", "min": Vector2(6.325, 22.560), "max": Vector2(7.675, 24.040), "height": 2.500, "space": "jardim_inverno"},
	{"id": "arvore_jardim_1", "min": Vector2(15.500, 23.000), "max": Vector2(17.975, 24.940), "height": 2.500, "space": "jardim_inverno"},
	{"id": "cadeira_jardim_0", "min": Vector2(9.750, 23.922), "max": Vector2(10.250, 24.377), "height": 0.920, "space": "jardim_inverno"},
	{"id": "cadeira_jardim_1", "min": Vector2(14.550, 23.922), "max": Vector2(15.050, 24.377), "height": 0.920, "space": "jardim_inverno"},
	{"id": "vaso_jardim_0", "min": Vector2(10.172, 26.049), "max": Vector2(10.828, 26.551), "height": 0.372, "space": "jardim_inverno"},
	{"id": "vaso_jardim_1", "min": Vector2(13.872, 26.049), "max": Vector2(14.528, 26.551), "height": 0.372, "space": "jardim_inverno"},
	{"id": "vaso_jardim_2", "min": Vector2(16.072, 28.099), "max": Vector2(16.728, 28.601), "height": 0.372, "space": "jardim_inverno"},
	{"id": "vaso_acesso", "min": Vector2(-3.728, 27.349), "max": Vector2(-3.072, 27.851), "height": 0.372, "space": "jardim_acesso"},
	{"id": "busto_galeria_0", "min": Vector2(2.490, 0.000), "max": Vector2(2.910, 0.320), "height": 1.510, "space": "galeria", "floor": GALLERY_FLOOR},
	{"id": "busto_galeria_1", "min": Vector2(3.990, 0.000), "max": Vector2(4.410, 0.320), "height": 1.510, "space": "galeria", "floor": GALLERY_FLOOR},
	{"id": "busto_galeria_2", "min": Vector2(9.640, 0.000), "max": Vector2(10.060, 0.320), "height": 1.510, "space": "galeria", "floor": GALLERY_FLOOR},
	{"id": "vaso_galeria_0", "min": Vector2(0.072, 0.029), "max": Vector2(0.728, 0.531), "height": 0.372, "space": "galeria", "floor": GALLERY_FLOOR},
	{"id": "canhao_oeste", "min": Vector2(1.725, 2.775), "max": Vector2(2.575, 4.325), "height": 0.540, "space": "galeria_oeste", "floor": GALLERY_FLOOR},
	{"id": "canhao_leste", "min": Vector2(12.055, 1.855), "max": Vector2(12.905, 3.305), "height": 0.540, "space": "galeria_leste", "floor": GALLERY_FLOOR},
	{"id": "vaso_galeria_1", "min": Vector2(3.222, 4.299), "max": Vector2(3.878, 4.801), "height": 0.372, "space": "galeria_oeste", "floor": GALLERY_FLOOR},
	{"id": "comoda_vao", "min": Vector2(6.549, 4.160), "max": Vector2(7.751, 4.740), "height": 1.212, "space": "galeria_vao", "floor": GALLERY_FLOOR},
	{"id": "busto_vao", "min": Vector2(8.640, 4.680), "max": Vector2(9.060, 5.000), "height": 1.510, "space": "galeria_vao", "floor": GALLERY_FLOOR},
	{"id": "vaso_vao", "min": Vector2(6.022, 4.299), "max": Vector2(6.678, 4.801), "height": 0.372, "space": "galeria_vao", "floor": GALLERY_FLOOR},
	{"id": "comoda_galeria_leste", "min": Vector2(12.060, 2.549), "max": Vector2(12.640, 3.751), "height": 1.212, "space": "galeria_leste", "floor": GALLERY_FLOOR},
	{"id": "vaso_galeria_leste", "min": Vector2(12.022, 1.999), "max": Vector2(12.678, 2.501), "height": 0.372, "space": "galeria_leste", "floor": GALLERY_FLOOR},
	{"id": "comoda_corredor_0", "min": Vector2(18.799, 9.410), "max": Vector2(20.001, 9.990), "height": 1.212, "space": "corredor_leste", "floor": GALLERY_FLOOR},
	{"id": "comoda_corredor_1", "min": Vector2(24.049, 9.410), "max": Vector2(25.251, 9.990), "height": 1.212, "space": "corredor_leste", "floor": GALLERY_FLOOR},
	{"id": "vaso_corredor_0", "min": Vector2(16.522, 9.449), "max": Vector2(17.178, 9.951), "height": 0.372, "space": "corredor_oeste", "floor": GALLERY_FLOOR},
	{"id": "vaso_corredor_1", "min": Vector2(25.842, 9.499), "max": Vector2(26.498, 10.001), "height": 0.372, "space": "corredor_leste", "floor": GALLERY_FLOOR},
	{"id": "vaso_corredor_2", "min": Vector2(20.672, 9.449), "max": Vector2(21.328, 9.951), "height": 0.372, "space": "corredor_leste", "floor": GALLERY_FLOOR},
	{"id": "arvore_corredor_0", "min": Vector2(19.850, 7.200), "max": Vector2(20.550, 7.900), "height": 1.800, "space": "corredor_leste", "floor": GALLERY_FLOOR},
	{"id": "arvore_corredor_1", "min": Vector2(23.800, 7.200), "max": Vector2(24.500, 7.900), "height": 1.800, "space": "corredor_leste", "floor": GALLERY_FLOOR},
	{"id": "cadeira_corredor", "min": Vector2(23.273, 9.100), "max": Vector2(23.727, 9.600), "height": 0.920, "space": "corredor_leste", "floor": GALLERY_FLOOR},
	{"id": "vaso_patamar", "min": Vector2(24.522, 5.029), "max": Vector2(25.178, 5.531), "height": 0.372, "space": "patamar_servico", "floor": GALLERY_FLOOR},
	{"id": "criado_norte", "min": Vector2(-8.125, 0.275), "max": Vector2(-7.575, 0.725), "height": 0.720, "space": "quarto_norte", "floor": GALLERY_FLOOR},
	{"id": "estante_norte_0", "min": Vector2(-4.050, 2.420), "max": Vector2(-3.150, 2.820), "height": 2.200, "space": "quarto_norte", "floor": GALLERY_FLOOR},
	{"id": "estante_norte_1", "min": Vector2(-2.650, 2.420), "max": Vector2(-1.750, 2.820), "height": 2.200, "space": "quarto_norte", "floor": GALLERY_FLOOR},
	{"id": "cadeira_norte", "min": Vector2(-4.928, 2.100), "max": Vector2(-4.473, 2.600), "height": 0.920, "space": "quarto_norte", "floor": GALLERY_FLOOR},
	{"id": "vaso_norte", "min": Vector2(-1.278, 2.349), "max": Vector2(-0.622, 2.851), "height": 0.372, "space": "quarto_norte", "floor": GALLERY_FLOOR},
	{"id": "criado_suite_0", "min": Vector2(-8.125, 6.025), "max": Vector2(-7.575, 6.475), "height": 0.720, "space": "suite", "floor": GALLERY_FLOOR},
	{"id": "criado_suite_1", "min": Vector2(-8.125, 8.525), "max": Vector2(-7.575, 8.975), "height": 0.720, "space": "suite", "floor": GALLERY_FLOOR},
	{"id": "comoda_suite_0", "min": Vector2(-6.101, 9.420), "max": Vector2(-4.899, 10.000), "height": 1.212, "space": "suite", "floor": GALLERY_FLOOR},
	{"id": "comoda_suite_1", "min": Vector2(-4.801, 9.420), "max": Vector2(-3.599, 10.000), "height": 1.212, "space": "suite", "floor": GALLERY_FLOOR},
	{"id": "estante_suite_0", "min": Vector2(-1.075, 5.050), "max": Vector2(-0.625, 6.150), "height": 2.200, "space": "suite", "floor": GALLERY_FLOOR},
	{"id": "estante_suite_1", "min": Vector2(-1.075, 6.150), "max": Vector2(-0.625, 7.250), "height": 2.200, "space": "suite", "floor": GALLERY_FLOOR},
	{"id": "cadeira_suite", "min": Vector2(-5.050, 7.173), "max": Vector2(-4.550, 7.628), "height": 0.920, "space": "suite", "floor": GALLERY_FLOOR},
	{"id": "vaso_suite_0", "min": Vector2(-10.478, 3.649), "max": Vector2(-9.822, 4.151), "height": 0.372, "space": "suite", "floor": GALLERY_FLOOR},
	{"id": "vaso_suite_1", "min": Vector2(-10.478, 9.399), "max": Vector2(-9.822, 9.901), "height": 0.372, "space": "suite", "floor": GALLERY_FLOOR},
	{"id": "vaso_suite_2", "min": Vector2(-1.278, 9.399), "max": Vector2(-0.622, 9.901), "height": 0.372, "space": "suite", "floor": GALLERY_FLOOR},
	{"id": "cadeira_musica_0", "min": Vector2(27.150, 10.573), "max": Vector2(27.650, 11.027), "height": 0.920, "space": "musica", "floor": GALLERY_FLOOR},
	{"id": "cadeira_musica_1", "min": Vector2(27.150, 11.372), "max": Vector2(27.650, 11.828), "height": 0.920, "space": "musica", "floor": GALLERY_FLOOR},
	{"id": "cadeira_musica_2", "min": Vector2(27.150, 12.172), "max": Vector2(27.650, 12.628), "height": 0.920, "space": "musica", "floor": GALLERY_FLOOR},
	{"id": "comoda_musica", "min": Vector2(27.160, 12.849), "max": Vector2(27.740, 14.051), "height": 1.212, "space": "musica", "floor": GALLERY_FLOOR},
	{"id": "vaso_musica_0", "min": Vector2(27.072, 10.149), "max": Vector2(27.728, 10.651), "height": 0.372, "space": "musica", "floor": GALLERY_FLOOR},
	{"id": "vaso_musica_1", "min": Vector2(33.272, 13.299), "max": Vector2(33.928, 13.801), "height": 0.372, "space": "musica", "floor": GALLERY_FLOOR},
	{"id": "cadeira_musica_3", "min": Vector2(32.350, 11.672), "max": Vector2(32.850, 12.128), "height": 0.920, "space": "musica", "floor": GALLERY_FLOOR},
	{"id": "escrivaninha_observatorio", "min": Vector2(27.800, 4.975), "max": Vector2(29.000, 5.525), "height": 0.750, "space": "observatorio", "floor": GALLERY_FLOOR},
	{"id": "cadeira_observatorio", "min": Vector2(30.175, 5.000), "max": Vector2(30.625, 5.500), "height": 0.920, "space": "observatorio", "floor": GALLERY_FLOOR},
	{"id": "vaso_observatorio_0", "min": Vector2(31.672, 5.049), "max": Vector2(32.328, 5.551), "height": 0.372, "space": "observatorio", "floor": GALLERY_FLOOR},
	{"id": "vaso_observatorio_1", "min": Vector2(33.272, 7.399), "max": Vector2(33.928, 7.901), "height": 0.372, "space": "observatorio", "floor": GALLERY_FLOOR},
]
const RAMPS := [
	{"id": "lance_oeste", "space": "salao", "min": Vector2(4, 2), "max": Vector2(6, 6),
		"axis": "z", "y_at_min": GALLERY_FLOOR, "y_at_max": 0.0},
	{"id": "lance_leste", "space": "salao", "min": Vector2(10, 2), "max": Vector2(12, 6),
		"axis": "z", "y_at_min": GALLERY_FLOOR, "y_at_max": 0.0},
	{"id": "escada_servico", "space": "cozinha", "min": Vector2(18, 5), "max": Vector2(24.5, 7),
		"axis": "x", "y_at_min": 0.0, "y_at_max": GALLERY_FLOOR},
]
# O metro ao sul do espaço do patamar coincide com o corredor.
const SERVICE_LANDING := {"id": "patamar_servico", "space": "cozinha",
	"min": Vector2(24.5, 5), "max": Vector2(26.5, 8), "y": GALLERY_FLOOR}
static var LANDINGS: Array = _landings()

static func _landings() -> Array:
	var result := [SERVICE_LANDING]
	for entry in SPACES + DOORS:
		if space_floor(entry) > 0.0 and entry["id"] != SERVICE_LANDING["id"]:
			var id: String = entry["id"]
			result.append({"id": "piso_" + id if entry.has("room") else id, "space": entry.get("room", id),
				"min": entry["min"], "max": entry["max"], "y": GALLERY_FLOOR})
	return result
const HALL_RAILS := [
	Rect2(4, 2, 0.1, 4), Rect2(5.95, 2, 0.1, 4),
	Rect2(9.95, 2, 0.1, 4), Rect2(11.9, 2, 0.1, 4),
]
const SERVICE_RAILS := [
	Rect2(18, 6.9, 6.5, 0.1),
]
const UPPER_RAILS := [
	Rect2(0, 4.9, 4, 0.1), Rect2(6, 4.9, 4, 0.1), Rect2(12, 4.9, 2.5, 0.1),
	Rect2(14.5, 5, 0.1, 2), Rect2(14.5, 6.9, 1.5, 0.1),
	Rect2(16.5, 9.9, 10, 0.1), Rect2(17.9, 5, 0.1, 2),
]
const SPAWNS := [
	{"id": "spawn_salao", "space": "salao", "position": Vector2(1.8, 12.6), "floor": 0.0, "face": Vector2(8, 10)},
	{"id": "spawn_biblioteca", "space": "biblioteca", "position": Vector2(-1.4, 13.3), "floor": 0.0, "face": Vector2(-0.25, 8)},
	{"id": "spawn_jantar", "space": "jantar", "position": Vector2(7.2, 21.6), "floor": 0.0, "face": Vector2(8, 14.25)},
	{"id": "spawn_hospedes", "space": "hospedes", "position": Vector2(-6.5, 18.8), "floor": 0.0, "face": Vector2(-8.5, 14.25)},
	{"id": "spawn_galeria", "space": "galeria_leste", "position": Vector2(14.4, 3.4), "floor": GALLERY_FLOOR, "face": Vector2(8, 1)},
	{"id": "spawn_quarto_norte", "space": "quarto_norte", "position": Vector2(-2.2, 1.5), "floor": GALLERY_FLOOR, "face": Vector2(0, 1)},
	{"id": "spawn_suite", "space": "suite", "position": Vector2(-4.8, 4.6), "floor": GALLERY_FLOOR, "face": Vector2(0, 4)},
	{"id": "spawn_musica", "space": "musica", "position": Vector2(28.6, 9.4), "floor": GALLERY_FLOOR, "face": Vector2(30, 11)},
]
const PICKUPS := [
	{"id": "weapon_0", "type": "weapon", "weapon_id": "hunting_rifle", "space": "salao", "position": Vector2(10.8, 12.8), "floor": 0.0},
	{"id": "weapon_1", "type": "weapon", "weapon_id": "hunting_rifle", "space": "galeria", "position": Vector2(2.0, 0.8), "floor": GALLERY_FLOOR},
	{"id": "weapon_2", "type": "weapon", "weapon_id": "hunting_rifle", "space": "jantar", "position": Vector2(7.5, 16.2), "floor": 0.0},
	{"id": "weapon_3", "type": "weapon", "weapon_id": "hunting_rifle", "space": "cozinha", "position": Vector2(25.2, 13.0), "floor": 0.0},
	{"id": "weapon_4", "type": "weapon", "weapon_id": "aug", "space": "biblioteca", "position": Vector2(-8.5, 8.0), "floor": 0.0},
	{"id": "weapon_5", "type": "weapon", "weapon_id": "aug", "space": "galeria", "position": Vector2(11.4, 0.6), "floor": GALLERY_FLOOR},
	{"id": "weapon_6", "type": "weapon", "weapon_id": "aug", "space": "observatorio", "position": Vector2(33.4, 5.6), "floor": GALLERY_FLOOR},
	{"id": "weapon_7", "type": "weapon", "weapon_id": "aug", "space": "salao", "position": Vector2(6.2, 0.6), "floor": 0.0},
	{"id": "weapon_8", "type": "weapon", "weapon_id": "common_pistol", "space": "hospedes", "position": Vector2(-9.8, 16.0), "floor": 0.0},
	{"id": "weapon_9", "type": "weapon", "weapon_id": "common_pistol", "space": "jardim_inverno", "position": Vector2(17.5, 27.2), "floor": 0.0},
	{"id": "weapon_10", "type": "weapon", "weapon_id": "common_pistol", "space": "suite", "position": Vector2(-8.8, 4.8), "floor": GALLERY_FLOOR},
	{"id": "weapon_11", "type": "weapon", "weapon_id": "common_pistol", "space": "jantar", "position": Vector2(12.2, 18.7), "floor": 0.0},
	{"id": "ammo_0", "type": "ammo", "space": "lavabo", "position": Vector2(-0.3, 18.7), "floor": 0.0},
	{"id": "ammo_1", "type": "ammo", "space": "banheiro_marmore", "position": Vector2(-3.3, 25.2), "floor": 0.0},
	{"id": "ammo_2", "type": "ammo", "space": "jardim_inverno", "position": Vector2(11.2, 24.2), "floor": 0.0},
	{"id": "ammo_3", "type": "ammo", "space": "salao", "position": Vector2(14.7, 0.7), "floor": 0.0},
	{"id": "ammo_4", "type": "ammo", "space": "corredor_oeste", "position": Vector2(17.2, 8.2), "floor": GALLERY_FLOOR},
	{"id": "ammo_5", "type": "ammo", "space": "galeria_vao", "position": Vector2(8.7, 4.2), "floor": GALLERY_FLOOR},
	{"id": "ammo_6", "type": "ammo", "space": "jantar", "position": Vector2(17.7, 18.2), "floor": 0.0},
	{"id": "ammo_7", "type": "ammo", "space": "salao", "position": Vector2(2.2, 8.7), "floor": 0.0},
	{"id": "ammo_8", "type": "ammo", "space": "quarto_norte", "position": Vector2(-5.3, 0.7), "floor": GALLERY_FLOOR},
	{"id": "ammo_9", "type": "ammo", "space": "corredor_leste", "position": Vector2(22.2, 9.2), "floor": GALLERY_FLOOR},
	{"id": "ammo_10", "type": "ammo", "space": "jardim_acesso", "position": Vector2(0.2, 28.2), "floor": 0.0},
	{"id": "ammo_11", "type": "ammo", "space": "jardim_inverno", "position": Vector2(7.3, 28.4), "floor": 0.0},
	{"id": "health_0", "type": "health", "space": "biblioteca", "position": Vector2(-5.5, 13.0), "floor": 0.0},
	{"id": "health_1", "type": "health", "space": "banheiro_marmore", "position": Vector2(4.0, 25.2), "floor": 0.0},
	{"id": "health_2", "type": "health", "space": "cozinha", "position": Vector2(25.2, 8.2), "floor": 0.0},
	{"id": "health_3", "type": "health", "space": "musica", "position": Vector2(32.5, 10.5), "floor": GALLERY_FLOOR},
	{"id": "health_4", "type": "health", "space": "suite", "position": Vector2(-3.0, 9.3), "floor": GALLERY_FLOOR},
]

static var enabled := OS.get_environment("OSSUSPEITOS_MAP") == "nocturna_salao"

static func rect(entry: Dictionary) -> Rect2:
	return Rect2(entry["min"], (entry["max"] as Vector2) - (entry["min"] as Vector2))

static func space_floor(entry: Dictionary) -> float:
	return float(entry.get("floor", 0.0))

static func floor_height(x: float, z: float) -> float:
	return walk_height(x, z, GALLERY_FLOOR + MansionMap.BODY_CENTER_HEIGHT)

static func walk_height(x: float, z: float, body_y: float) -> float:
	var point := Vector2(x, z)
	for ramp in RAMPS:
		var area := rect(ramp)
		if area.has_point(point):
			var axis := 0 if ramp["axis"] == "x" else 1
			var t := inverse_lerp(area.position[axis], area.end[axis], point[axis])
			return lerpf(ramp["y_at_min"], ramp["y_at_max"], t)
	if body_y - MansionMap.BODY_CENTER_HEIGHT > GALLERY_FLOOR * 0.5:
		for landing in LANDINGS:
			if rect(landing).has_point(point):
				return GALLERY_FLOOR
	return 0.0

static func space_at(point: Vector2, y: float = 0.0) -> Dictionary:
	var result := {}
	for entry in SPACES:
		var floor_y := space_floor(entry)
		if floor_y <= y and y <= float(entry["ceiling"]) and rect(entry).has_point(point):
			if result.is_empty() or floor_y > space_floor(result):
				result = entry
	if not result.is_empty():
		return result
	for door in DOORS:
		if y >= space_floor(door) and rect(door).has_point(point):
			for entry in SPACES:
				if entry["id"] == door["room"] and y <= float(entry["ceiling"]):
					return entry
	return {}

static func pickups() -> Array:
	return PICKUPS

static func pickups_of_type(kind: String) -> Array:
	return PICKUPS.filter(func(entry): return str(entry["type"]) == kind)

static func weapon_id_of(pickup_id: String) -> String:
	for entry in PICKUPS:
		if str(entry["id"]) == pickup_id and str(entry["type"]) == "weapon":
			return str(entry.get("weapon_id", "common_pistol"))
	return "common_pistol"

static func item_floor(entry: Dictionary) -> float:
	return float(entry.get("floor", 0.0))

static func item_point(entry: Dictionary) -> Vector2:
	return entry["position"]

static func item_position(entry: Dictionary, height: float) -> Vector3:
	var point: Vector2 = entry["position"]
	return Vector3(point.x, height + item_floor(entry), point.y)

static func spawn_points() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for entry in SPAWNS:
		result.append(item_position(entry, MansionMap.BODY_CENTER_HEIGHT))
	return result

static func spawn_yaw_at(index: int) -> float:
	var entry: Dictionary = SPAWNS[index]
	var from: Vector2 = entry["position"]
	var to: Vector2 = entry["face"]
	return atan2(-(to.x - from.x), -(to.y - from.y))

static func pickup_positions() -> Array:
	var result: Array = []
	for entry in PICKUPS:
		result.append(item_position(entry, MansionMap.PICKUP_HEIGHT))
	return result

static func _cells(entries: Array, floor_y: float) -> Dictionary:
	var cells := {}
	for entry in entries:
		if space_floor(entry) != floor_y:
			continue
		var area := rect(entry)
		var first := Vector2i(area.position / CELL)
		var end := Vector2i(area.end / CELL)
		for z in range(first.y, end.y):
			for x in range(first.x, end.x):
				cells[Vector2i(x, z)] = true
	return cells

static func _wall_cells(floor_cells: Dictionary) -> Dictionary:
	var wall_cells := {}
	for cell: Vector2i in floor_cells:
		for z in range(-1, 2):
			for x in range(-1, 2):
				var neighbor := cell + Vector2i(x, z)
				if not floor_cells.has(neighbor):
					wall_cells[neighbor] = true

	return wall_cells

static func _append_walls(result: Array, wall_cells: Dictionary, bottom: float, top: float, prefix: String) -> void:
	var cells := wall_cells.keys()
	cells.sort()
	for cell: Vector2i in cells:
		if wall_cells.has(cell - Vector2i(0, 1)):
			continue
		var length := 1
		while wall_cells.has(cell + Vector2i(0, length)):
			length += 1
		var wall := Rect2(Vector2(cell) * CELL, Vector2(CELL, length * CELL))
		result.append(_box("%s_x%d_z%d" % [prefix, cell.x, cell.y], "wall", wall, bottom, top, ""))

static func blockers() -> Array:
	var ground := _cells(SPACES + DOORS, 0.0)
	var ground_walls := _wall_cells(ground)
	var upper := _cells(SPACES + DOORS, GALLERY_FLOOR)
	var upper_walls := _wall_cells(upper)
	for cell in upper_walls.keys():
		if ground.has(cell) or ground_walls.has(cell):
			upper_walls.erase(cell)
	for cell in _cells(DOORS, GALLERY_FLOOR):
		ground_walls.erase(cell)
	# Onde o piso superior cruza uma parede térrea, mantenha só a parte sob a laje.
	var low_walls := {}
	for cell in ground_walls.keys():
		if upper.has(cell):
			low_walls[cell] = ground_walls[cell]
			ground_walls.erase(cell)
	var result: Array = []
	_append_walls(result, low_walls, 0.0, GALLERY_FLOOR, "wall_ate_galeria")
	_append_walls(result, ground_walls, 0.0, WALL_TOP, "wall")
	_append_walls(result, upper_walls, GALLERY_FLOOR, WALL_TOP, "wall_superior")
	# O piso da Biblioteca suprime a parede gerada no limite sul da Suíte.
	result.append(_box("parede_suite_sul", "wall", Rect2(MIN_X, 10, 10, 0.5), GALLERY_FLOOR, WALL_TOP, "suite"))
	for door in DOORS:
		var floor_y := space_floor(door)
		if floor_y > 0.0:
			result.append(_box("base_" + door["id"], "wall", rect(door), 0.0, floor_y, door["room"]))
		result.append(_box(door["id"], "lintel", rect(door), floor_y + MansionMap.DOOR_HEIGHT, WALL_TOP, door["room"]))
	for entry in SPACES:
		if entry["id"] in ["cozinha", "biblioteca"]:
			continue
		var ceiling: float = entry["ceiling"]
		var area := rect(entry).grow(CELL * 0.5) if space_floor(entry) == 0.0 else rect(entry)
		result.append(_box("teto_" + entry["id"], "ceiling", area, ceiling,
			ceiling + MansionMap.SLAB_THICKNESS, entry["id"]))
	result.append(_box("teto_cozinha", "ceiling", Rect2(16.5, 10, 10, 4), 3.5, 3.5 + MansionMap.SLAB_THICKNESS, "cozinha"))
	result.append(_box("teto_vao_cozinha", "ceiling", Rect2(16.5, 5, 10, 5), 7.0, WALL_TOP, "cozinha"))
	result.append(_box("teto_biblioteca", "ceiling", Rect2(MIN_X, 10, 10, 4), GALLERY_FLOOR,
		GALLERY_FLOOR + MansionMap.SLAB_THICKNESS, "biblioteca"))
	result.append(_box("teto_vao_biblioteca", "ceiling", Rect2(MIN_X, 5, 10, 5), 7.0, WALL_TOP, "biblioteca"))
	for item in FURNITURE:
		var bottom: float = item.get("floor", 0.0)
		result.append(_box(item["id"], "furniture", rect(item), bottom, bottom + item["height"], item.get("space", "salao")))
	for ramp in RAMPS:
		result.append(_box(ramp["id"], "furniture", rect(ramp), 0.0,
			maxf(ramp["y_at_min"], ramp["y_at_max"]), ramp["space"], true))
	for landing in LANDINGS:
		result.append(_box(landing["id"], "furniture", rect(landing), GALLERY_FLOOR - 0.1,
			GALLERY_FLOOR, landing["space"], true))
	for index in UPPER_RAILS.size():
		result.append(_box("corrimao_superior_%d" % index, "furniture", UPPER_RAILS[index], GALLERY_FLOOR, 4.5, ""))
	for index in HALL_RAILS.size():
		result.append(_box("corrimao_salao_%d" % index, "furniture", HALL_RAILS[index], 0.0, 4.5, "salao"))
	for index in SERVICE_RAILS.size():
		result.append(_box("corrimao_servico_%d" % index, "furniture", SERVICE_RAILS[index], 0.0, 4.5, "cozinha"))
	return result

static func _box(id: String, kind: String, area: Rect2, bottom: float, top: float, space: String,
		walkable := false) -> Dictionary:
	var center := area.get_center()
	var blocker := {"id": id, "kind": kind, "space": space,
		"center": Vector3(center.x, (bottom + top) * 0.5, center.y),
		"size": Vector3(area.size.x, top - bottom, area.size.y)}
	if walkable:
		blocker["walkable"] = true
	return blocker
