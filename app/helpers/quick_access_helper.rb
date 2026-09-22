module QuickAccessHelper
  def consulta_quick_access_items(origin:)
    warehouse = origin == "az"
    [
      { title: "LOG ON", category: "Aprendizado", icon: "bi-mortarboard", theme: "learning",
        description: "Seus cursos e treinamentos em um só lugar. Continue aprendendo para a rotina da operação.",
        action: "Acessar treinamentos", href: "https://ambev.beedoo.io/login", external: true },
      { title: "Rotograma", category: "Na estrada", icon: "bi-signpost-split", theme: "routes",
        description: "Escolha seu destino no mapa e consulte as orientações do trajeto antes de sair.",
        action: "Explorar localidades", href: warehouse ? rotogramas_path(origem: "az") : rotogramas_path, external: false },
      { title: "Relatos", category: "Segurança", icon: "bi-chat-square-text", theme: "reports",
        description: "Viu algo que merece atenção? Registre seu relato e contribua com a segurança da operação.",
        action: "Registrar um relato", href: "https://ginfo.inovess.com.br/relatos_2/index.php?codigo=2219990356|filial=7", external: true },
      { title: "Estacionamento", tab_title: "Layout", category: "Organização", icon: "bi-p-square", theme: "parking",
        description: "Confira o layout do estacionamento e encontre o local correto para cada veículo.",
        action: "Explorar o pátio", external: false,
        href: warehouse ? patio_path(origem: "az") : patio_path }
    ]
  end
end
