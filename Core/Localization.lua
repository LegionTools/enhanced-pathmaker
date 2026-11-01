local addonName, addon = ...

addon.Localization = addon.Localization or {}
local Localization = addon.Localization

Localization.languages = {
    {code="enUS", name="English"}, {code="deDE", name="Deutsch"},
    {code="frFR", name="Français"}, {code="itIT", name="Italiano"},
    {code="ukUA", name="Українська"}, {code="ruRU", name="Русский"},
    {code="esES", name="Español"}, {code="esMX", name="Español (Latinoamérica)"},
    {code="ptBR", name="Português (Brasil)"}, {code="plPL", name="Polski"},
    {code="koKR", name="한국어"}, {code="zhCN", name="简体中文"},
    {code="zhTW", name="繁體中文"},
}

local translations = {
    deDE={
        ["PathMaker Settings"]="PathMaker-Einstellungen", General="Allgemein", Herbalism="Kräuterkunde", Mining="Bergbau", ["Route Manager"]="Routenverwaltung", ["Route Generator"]="Routengenerator", ["Draw Mode"]="Zeichenmodus", ["General options"]="Allgemeine Optionen", Language="Sprache", ["Shown WoW Versions (Maps, Herbs & Mining)"]="Angezeigte WoW-Versionen (Karten, Kräuter & Bergbau)", ["Disable Messages"]="Meldungen deaktivieren", ["Minimap UI"]="Minikarten-UI", ["World Map"]="Weltkarte", ["Farm Mode"]="Farmmodus", ["Navigation Arrow"]="Navigationspfeil", ["Select All"]="Alle auswählen", ["Select None"]="Auswahl aufheben", ["Import Route"]="Route importieren", ["Export Selected"]="Auswahl exportieren", Search="Suchen",
    },
    frFR={
        ["PathMaker Settings"]="Paramètres de PathMaker", General="Général", Herbalism="Herboristerie", Mining="Minage", ["Route Manager"]="Gestion des itinéraires", ["Route Generator"]="Générateur d’itinéraires", ["Draw Mode"]="Mode dessin", ["General options"]="Options générales", Language="Langue", ["Shown WoW Versions (Maps, Herbs & Mining)"]="Versions de WoW affichées (cartes, plantes et minerais)", ["Disable Messages"]="Désactiver les messages", ["Minimap UI"]="Interface de la minicarte", ["World Map"]="Carte du monde", ["Farm Mode"]="Mode récolte", ["Navigation Arrow"]="Flèche de navigation", ["Select All"]="Tout sélectionner", ["Select None"]="Tout désélectionner", ["Import Route"]="Importer l’itinéraire", ["Export Selected"]="Exporter la sélection", Search="Rechercher",
    },
    itIT={
        ["PathMaker Settings"]="Impostazioni di PathMaker", General="Generale", Herbalism="Erbalismo", Mining="Estrazione", ["Route Manager"]="Gestione percorsi", ["Route Generator"]="Generatore percorsi", ["Draw Mode"]="Modalità disegno", ["General options"]="Opzioni generali", Language="Lingua", ["Shown WoW Versions (Maps, Herbs & Mining)"]="Versioni di WoW mostrate (mappe, erbe e minerali)", ["Disable Messages"]="Disattiva messaggi", ["Minimap UI"]="Interfaccia minimappa", ["World Map"]="Mappa del mondo", ["Farm Mode"]="Modalità raccolta", ["Navigation Arrow"]="Freccia di navigazione", ["Select All"]="Seleziona tutto", ["Select None"]="Deseleziona tutto", ["Import Route"]="Importa percorso", ["Export Selected"]="Esporta selezionato", Search="Cerca",
    },
    ukUA={
        ["PathMaker Settings"]="Налаштування PathMaker", General="Загальні", Herbalism="Травництво", Mining="Гірнича справа", ["Route Manager"]="Керування маршрутами", ["Route Generator"]="Генератор маршрутів", ["Draw Mode"]="Режим малювання", ["General options"]="Загальні параметри", Language="Мова", ["Shown WoW Versions (Maps, Herbs & Mining)"]="Показані версії WoW (мапи, трави й руда)", ["Disable Messages"]="Вимкнути повідомлення", ["Minimap UI"]="Інтерфейс мінімапи", ["World Map"]="Мапа світу", ["Farm Mode"]="Режим збору", ["Navigation Arrow"]="Навігаційна стрілка", ["Select All"]="Вибрати все", ["Select None"]="Зняти вибір", ["Import Route"]="Імпортувати маршрут", ["Export Selected"]="Експортувати вибране", Search="Пошук",
    },
    ruRU={
        ["PathMaker Settings"]="Настройки PathMaker", General="Общие", Herbalism="Травничество", Mining="Горное дело", ["Route Manager"]="Управление маршрутами", ["Route Generator"]="Генератор маршрутов", ["Draw Mode"]="Режим рисования", ["General options"]="Общие параметры", Language="Язык", ["Shown WoW Versions (Maps, Herbs & Mining)"]="Показываемые версии WoW (карты, травы и руда)", ["Disable Messages"]="Отключить сообщения", ["Minimap UI"]="Интерфейс мини-карты", ["World Map"]="Карта мира", ["Farm Mode"]="Режим сбора", ["Navigation Arrow"]="Стрелка навигации", ["Select All"]="Выбрать всё", ["Select None"]="Снять выбор", ["Import Route"]="Импорт маршрута", ["Export Selected"]="Экспорт выбранного", Search="Поиск",
        ["Verified Nodes Only"]="Только проверенные узлы", ["Only use nodes you have actually gathered on this server. Bundled/imported nodes that have not been confirmed yet are left out of generated routes."]="Использовать только узлы, которые вы реально собрали на этом сервере. Узлы из импортированного набора, ещё не подтверждённые сбором, в маршрут не попадут.",
    },
    esES={
        ["PathMaker Settings"]="Ajustes de PathMaker", General="General", Herbalism="Herboristería", Mining="Minería", ["Route Manager"]="Gestor de rutas", ["Route Generator"]="Generador de rutas", ["Draw Mode"]="Modo de dibujo", ["General options"]="Opciones generales", Language="Idioma", ["Shown WoW Versions (Maps, Herbs & Mining)"]="Versiones de WoW visibles (mapas, hierbas y minería)", ["Disable Messages"]="Desactivar mensajes", ["Minimap UI"]="Interfaz del minimapa", ["World Map"]="Mapa del mundo", ["Farm Mode"]="Modo de recolección", ["Navigation Arrow"]="Flecha de navegación", ["Select All"]="Seleccionar todo", ["Select None"]="Deseleccionar todo", ["Import Route"]="Importar ruta", ["Export Selected"]="Exportar selección", Search="Buscar",
    },
    esMX={
        ["PathMaker Settings"]="Configuración de PathMaker", General="General", Herbalism="Herboristería", Mining="Minería", ["Route Manager"]="Administrador de rutas", ["Route Generator"]="Generador de rutas", ["Draw Mode"]="Modo de dibujo", ["General options"]="Opciones generales", Language="Idioma", ["Shown WoW Versions (Maps, Herbs & Mining)"]="Versiones de WoW visibles (mapas, hierbas y minería)", ["Disable Messages"]="Desactivar mensajes", ["Minimap UI"]="Interfaz del minimapa", ["World Map"]="Mapa del mundo", ["Farm Mode"]="Modo de recolección", ["Navigation Arrow"]="Flecha de navegación", ["Select All"]="Seleccionar todo", ["Select None"]="Deseleccionar todo", ["Import Route"]="Importar ruta", ["Export Selected"]="Exportar selección", Search="Buscar",
    },
    ptBR={
        ["PathMaker Settings"]="Configurações do PathMaker", General="Geral", Herbalism="Herborismo", Mining="Mineração", ["Route Manager"]="Gerenciador de rotas", ["Route Generator"]="Gerador de rotas", ["Draw Mode"]="Modo de desenho", ["General options"]="Opções gerais", Language="Idioma", ["Shown WoW Versions (Maps, Herbs & Mining)"]="Versões do WoW exibidas (mapas, ervas e mineração)", ["Disable Messages"]="Desativar mensagens", ["Minimap UI"]="Interface do minimapa", ["World Map"]="Mapa-múndi", ["Farm Mode"]="Modo de coleta", ["Navigation Arrow"]="Seta de navegação", ["Select All"]="Selecionar tudo", ["Select None"]="Desmarcar tudo", ["Import Route"]="Importar rota", ["Export Selected"]="Exportar seleção", Search="Buscar",
    },
    plPL={
        ["PathMaker Settings"]="Ustawienia PathMaker", General="Ogólne", Herbalism="Zielarstwo", Mining="Górnictwo", ["Route Manager"]="Menedżer tras", ["Route Generator"]="Generator tras", ["Draw Mode"]="Tryb rysowania", ["General options"]="Opcje ogólne", Language="Język", ["Shown WoW Versions (Maps, Herbs & Mining)"]="Widoczne wersje WoW (mapy, zioła i górnictwo)", ["Disable Messages"]="Wyłącz komunikaty", ["Minimap UI"]="Interfejs minimapy", ["World Map"]="Mapa świata", ["Farm Mode"]="Tryb zbierania", ["Navigation Arrow"]="Strzałka nawigacji", ["Select All"]="Zaznacz wszystko", ["Select None"]="Odznacz wszystko", ["Import Route"]="Importuj trasę", ["Export Selected"]="Eksportuj zaznaczone", Search="Szukaj",
    },
    koKR={
        ["PathMaker Settings"]="PathMaker 설정", General="일반", Herbalism="약초채집", Mining="채광", ["Route Manager"]="경로 관리", ["Route Generator"]="경로 생성", ["Draw Mode"]="그리기 모드", ["General options"]="일반 설정", Language="언어", ["Shown WoW Versions (Maps, Herbs & Mining)"]="표시할 WoW 버전 (지도, 약초, 광물)", ["Disable Messages"]="메시지 끄기", ["Minimap UI"]="미니맵 UI", ["World Map"]="세계 지도", ["Farm Mode"]="채집 모드", ["Navigation Arrow"]="탐색 화살표", ["Select All"]="모두 선택", ["Select None"]="모두 해제", ["Import Route"]="경로 가져오기", ["Export Selected"]="선택 항목 내보내기", Search="검색",
    },
    zhCN={
        ["PathMaker Settings"]="PathMaker 设置", General="常规", Herbalism="草药学", Mining="采矿", ["Route Manager"]="路线管理", ["Route Generator"]="路线生成器", ["Draw Mode"]="绘制模式", ["General options"]="常规选项", Language="语言", ["Shown WoW Versions (Maps, Herbs & Mining)"]="显示的魔兽版本（地图、草药与采矿）", ["Disable Messages"]="禁用消息", ["Minimap UI"]="小地图界面", ["World Map"]="世界地图", ["Farm Mode"]="采集模式", ["Navigation Arrow"]="导航箭头", ["Select All"]="全选", ["Select None"]="取消全选", ["Import Route"]="导入路线", ["Export Selected"]="导出所选", Search="搜索",
    },
    zhTW={
        ["PathMaker Settings"]="PathMaker 設定", General="一般", Herbalism="草藥學", Mining="採礦", ["Route Manager"]="路線管理", ["Route Generator"]="路線產生器", ["Draw Mode"]="繪製模式", ["General options"]="一般選項", Language="語言", ["Shown WoW Versions (Maps, Herbs & Mining)"]="顯示的魔獸版本（地圖、草藥與採礦）", ["Disable Messages"]="停用訊息", ["Minimap UI"]="小地圖介面", ["World Map"]="世界地圖", ["Farm Mode"]="採集模式", ["Navigation Arrow"]="導航箭頭", ["Select All"]="全選", ["Select None"]="取消全選", ["Import Route"]="匯入路線", ["Export Selected"]="匯出所選", Search="搜尋",
    },
}

local supported = {enUS=true}
for _, language in ipairs(Localization.languages) do supported[language.code] = true end

function Localization:IsSupported(code) return supported[code] == true end
function Localization:GetLanguageName(code)
    for _, language in ipairs(self.languages) do
        if language.code == code then return language.name end
    end
    return "English"
end

function addon:GetLanguage()
    local code = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.language or "enUS"
    return supported[code] and code or "enUS"
end

function addon:Translate(text)
    local language = self:GetLanguage()
    local dictionary = translations[language]
    return dictionary and dictionary[text] or text
end

