import 'package:flutter/material.dart';
import '../app_theme.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final List<String> _baseData = [
    "Projeto Elétrico Alpha",
    "Normas ABNT 2026",
    "Cálculo Estrutural Beta",
    "Planta Hidráulica Omega",
    "Documentação TOT v1",
    "Histórico de Interligações",
    "Relatório de Eficiência",
    "Diretrizes de Segurança"
  ];
  List<String> _filteredData = [];
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _filteredData = _baseData;
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();
  }

  void _filterData(String query) {
    setState(() {
      _filteredData = _baseData
          .where((item) => item.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildGradientAppBar(title: 'Pesquisa na Base TOT'),
      body: SlideTransition(
        position: _slideAnimation,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                onChanged: _filterData,
                decoration: const InputDecoration(
                  labelText: 'Buscar projetos, normas...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _filteredData.isEmpty
                    ? const Center(
                        child: Text("Nenhum projeto encontrado.",
                            style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: _filteredData.length,
                        itemBuilder: (context, index) {
                          return Card(
                            elevation: 2,
                            child: ListTile(
                              leading: const Icon(Icons.folder,
                                  color: AppColors.primary),
                              title: Text(_filteredData[index]),
                              onTap: () =>
                                  Navigator.pushNamed(context, '/details'),
                            ),
                          );
                        },
                      ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
