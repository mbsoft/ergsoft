import Foundation

/// Lightweight in-app localization so the language can be switched without restarting.
/// Usage: L10n.t("workout") — falls back to English, then to the key.
enum L10n {
    nonisolated(unsafe) static var language: AppLanguage = .en

    static func t(_ key: String) -> String {
        table[language]?[key] ?? table[.en]?[key] ?? key
    }

    private static let table: [AppLanguage: [String: String]] = [
        .en: [
            "workout": "Workout", "stats": "Stats", "history": "History", "devices": "Devices", "settings": "Settings",
            "start": "Start", "pause": "Pause", "resume": "Resume", "finish": "Finish",
            "time": "Time", "meters": "Meters", "distance": "Distance", "pace": "Pace", "watts": "Watts", "heart": "Heart", "cal": "Cal",
            "avg_pace": "Avg pace", "strokes": "strokes", "no_machine": "No machine",
            "units": "Units", "metric": "Metric", "imperial": "Imperial", "language": "Language", "appearance": "Appearance", "system": "System", "light": "Light", "dark": "Dark", "country": "Country",
            "dob": "Date of birth", "weight": "Weight", "max_hr": "Max heart rate", "derived_from_age": "from age (220 − age)",
            "hr_zones": "Heart rate zones", "profile": "Profile", "benchmarks": "Benchmarks", "integrations": "Integrations",
            "rower": "Rower", "bike": "Bike", "not_set": "Not set", "coming_soon": "Coming soon", "connect": "Connect",
            "bench.ftp": "FTP (20 min power)", "bench.max": "Max power", "bench.spi": "Stroke Power Index",
            "bench.spi_help": "Average watts ÷ stroke rate — work per stroke. Higher means more power per stroke at a given rate.",
            "bench.imperial_note": "Imperial selected: distances show the nearest common imperial benchmark.",
            "period": "Time period", "last7": "Last 7 days", "last30": "Last 30 days", "last90": "Last 90 days", "year": "This year", "all": "All time",
            "overall": "Overall stats", "total_meters": "Total distance", "total_time": "Total time", "active_days": "Active days",
            "total_cal": "Total calories", "avg_watts": "Average watts", "avg_rate": "Average rate", "sessions": "Sessions",
            "no_data": "No workouts in this period", "machine": "Machine", "all_machines": "All",
        ],
        .frCA: [
            "workout": "Entraînement", "stats": "Statistiques", "history": "Historique", "devices": "Appareils", "settings": "Réglages",
            "start": "Démarrer", "pause": "Pause", "resume": "Reprendre", "finish": "Terminer",
            "time": "Temps", "meters": "Mètres", "distance": "Distance", "pace": "Allure", "watts": "Watts", "heart": "Cœur", "cal": "Cal",
            "avg_pace": "Allure moy.", "strokes": "coups", "no_machine": "Aucun appareil",
            "units": "Unités", "metric": "Métrique", "imperial": "Impérial", "language": "Langue", "appearance": "Apparence", "system": "Système", "light": "Clair", "dark": "Sombre", "country": "Pays",
            "dob": "Date de naissance", "weight": "Poids", "max_hr": "FC maximale", "derived_from_age": "selon l'âge (220 − âge)",
            "hr_zones": "Zones de fréquence cardiaque", "profile": "Profil", "benchmarks": "Références", "integrations": "Intégrations",
            "rower": "Rameur", "bike": "Vélo", "not_set": "Non défini", "coming_soon": "Bientôt", "connect": "Connecter",
            "bench.ftp": "FTP (puissance 20 min)", "bench.max": "Puissance max", "bench.spi": "Indice de puissance par coup",
            "bench.spi_help": "Watts moyens ÷ cadence — travail par coup. Plus élevé = plus de puissance par coup à une cadence donnée.",
            "bench.imperial_note": "Unités impériales : les distances affichent la référence impériale courante la plus proche.",
            "period": "Période", "last7": "7 derniers jours", "last30": "30 derniers jours", "last90": "90 derniers jours", "year": "Cette année", "all": "Depuis le début",
            "overall": "Statistiques globales", "total_meters": "Distance totale", "total_time": "Temps total", "active_days": "Jours actifs",
            "total_cal": "Calories totales", "avg_watts": "Watts moyens", "avg_rate": "Cadence moyenne", "sessions": "Séances",
            "no_data": "Aucun entraînement pour cette période", "machine": "Appareil", "all_machines": "Tous",
        ],
        .esMX: [
            "workout": "Entrenamiento", "stats": "Estadísticas", "history": "Historial", "devices": "Dispositivos", "settings": "Ajustes",
            "start": "Iniciar", "pause": "Pausar", "resume": "Reanudar", "finish": "Terminar",
            "time": "Tiempo", "meters": "Metros", "distance": "Distancia", "pace": "Ritmo", "watts": "Watts", "heart": "Pulso", "cal": "Cal",
            "avg_pace": "Ritmo prom.", "strokes": "paladas", "no_machine": "Sin máquina",
            "units": "Unidades", "metric": "Métrico", "imperial": "Imperial", "language": "Idioma", "appearance": "Apariencia", "system": "Sistema", "light": "Claro", "dark": "Oscuro", "country": "País",
            "dob": "Fecha de nacimiento", "weight": "Peso", "max_hr": "FC máxima", "derived_from_age": "según edad (220 − edad)",
            "hr_zones": "Zonas de frecuencia cardíaca", "profile": "Perfil", "benchmarks": "Marcas", "integrations": "Integraciones",
            "rower": "Remo", "bike": "Bici", "not_set": "Sin definir", "coming_soon": "Próximamente", "connect": "Conectar",
            "bench.ftp": "FTP (potencia 20 min)", "bench.max": "Potencia máxima", "bench.spi": "Índice de potencia por palada",
            "bench.spi_help": "Watts promedio ÷ cadencia — trabajo por palada. Mayor = más potencia por palada a una cadencia dada.",
            "bench.imperial_note": "Unidades imperiales: las distancias muestran la marca imperial común más cercana.",
            "period": "Periodo", "last7": "Últimos 7 días", "last30": "Últimos 30 días", "last90": "Últimos 90 días", "year": "Este año", "all": "Todo",
            "overall": "Estadísticas generales", "total_meters": "Distancia total", "total_time": "Tiempo total", "active_days": "Días activos",
            "total_cal": "Calorías totales", "avg_watts": "Watts promedio", "avg_rate": "Cadencia promedio", "sessions": "Sesiones",
            "no_data": "Sin entrenamientos en este periodo", "machine": "Máquina", "all_machines": "Todas",
        ],
        .ptBR: [
            "workout": "Treino", "stats": "Estatísticas", "history": "Histórico", "devices": "Dispositivos", "settings": "Ajustes",
            "start": "Iniciar", "pause": "Pausar", "resume": "Retomar", "finish": "Concluir",
            "time": "Tempo", "meters": "Metros", "distance": "Distância", "pace": "Ritmo", "watts": "Watts", "heart": "Coração", "cal": "Cal",
            "avg_pace": "Ritmo médio", "strokes": "remadas", "no_machine": "Sem máquina",
            "units": "Unidades", "metric": "Métrico", "imperial": "Imperial", "language": "Idioma", "appearance": "Aparência", "system": "Sistema", "light": "Claro", "dark": "Escuro", "country": "País",
            "dob": "Data de nascimento", "weight": "Peso", "max_hr": "FC máxima", "derived_from_age": "pela idade (220 − idade)",
            "hr_zones": "Zonas de frequência cardíaca", "profile": "Perfil", "benchmarks": "Referências", "integrations": "Integrações",
            "rower": "Remo", "bike": "Bike", "not_set": "Não definido", "coming_soon": "Em breve", "connect": "Conectar",
            "bench.ftp": "FTP (potência 20 min)", "bench.max": "Potência máxima", "bench.spi": "Índice de potência por remada",
            "bench.spi_help": "Watts médios ÷ cadência — trabalho por remada. Maior = mais potência por remada numa dada cadência.",
            "bench.imperial_note": "Unidades imperiais: as distâncias mostram a referência imperial comum mais próxima.",
            "period": "Período", "last7": "Últimos 7 dias", "last30": "Últimos 30 dias", "last90": "Últimos 90 dias", "year": "Este ano", "all": "Tudo",
            "overall": "Estatísticas gerais", "total_meters": "Distância total", "total_time": "Tempo total", "active_days": "Dias ativos",
            "total_cal": "Calorias totais", "avg_watts": "Watts médios", "avg_rate": "Cadência média", "sessions": "Sessões",
            "no_data": "Nenhum treino neste período", "machine": "Máquina", "all_machines": "Todas",
        ],
    ]
}
