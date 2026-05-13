import 'package:flutter/material.dart';
import '../app_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _chatController = TextEditingController();
  final List<String> _messages = [
    "Olá! Sou o TOT, seu assistente preditivo. Como posso ajudar?"
  ];
  bool _isDark = true;

  void _sendMessage() {
    if (_chatController.text.trim().isEmpty) return;
    setState(() {
      _messages.add("Você: ${_chatController.text}");
      _messages.add("TOT: Processando consulta na base de projetos...");
      _chatController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: _isDark ? AppColors.surface : Colors.grey[100],
      ),
      child: Scaffold(
        appBar: buildGradientAppBar(title: 'Chat TOT'),
        drawer: Drawer(
          backgroundColor: AppColors.cardDark,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const DrawerHeader(
                decoration: BoxDecoration(color: AppColors.primaryDark),
                child: Text('TOT Menu',
                    style: TextStyle(color: Colors.white, fontSize: 24)),
              ),
              ListTile(
                leading: const Icon(Icons.chat, color: AppColors.textPrimary),
                title: const Text('Novo Chat',
                    style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  setState(() => _messages.clear());
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.help_outline,
                    color: AppColors.textPrimary),
                title: const Text('FAQ',
                    style: TextStyle(color: AppColors.textPrimary)),
                onTap: () => Navigator.pushNamed(context, '/faq'),
              ),
              SwitchListTile(
                title: const Text('Modo Escuro',
                    style: TextStyle(color: AppColors.textPrimary)),
                value: _isDark,
                activeColor: AppColors.accent,
                onChanged: (val) => setState(() => _isDark = val),
              )
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final isUser = _messages[index].startsWith("Você:");
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isUser
                          ? AppColors.primaryLight.withValues(alpha: 0.2)
                          : AppColors.cardDark,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color:
                              isUser ? AppColors.primary : Colors.transparent),
                    ),
                    child: Text(
                      _messages[index],
                      style: TextStyle(
                          color:
                              _isDark ? AppColors.textPrimary : Colors.black87),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      style: TextStyle(
                          color:
                              _isDark ? AppColors.textPrimary : Colors.black),
                      decoration: InputDecoration(
                        hintText: 'Digite sua dúvida...',
                        hintStyle:
                            const TextStyle(color: AppColors.textSecondary),
                        filled: true,
                        fillColor: _isDark ? AppColors.cardDark : Colors.white,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24)),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: AppColors.primary),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
