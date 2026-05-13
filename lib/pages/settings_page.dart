import 'package:flutter/material.dart';
import '../app_theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildGradientAppBar(title: 'Configurações'),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('PREFERÊNCIAS',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
          SwitchListTile(
            title: const Text('Notificações'),
            value: _notificationsEnabled,
            activeColor: AppColors.primary,
            onChanged: (val) => setState(() => _notificationsEnabled = val),
          ),
          SwitchListTile(
            title: const Text('Modo Escuro'),
            value: _darkModeEnabled,
            activeColor: AppColors.primary,
            onChanged: (val) => setState(() => _darkModeEnabled = val),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('CONTA',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.lock),
            title: const Text('Alterar Senha'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Excluir Conta',
                style: TextStyle(color: Colors.red)),
            onTap: () {},
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('SOBRE',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
          const ListTile(
            leading: Icon(Icons.info),
            title: Text('Versão do App'),
            subtitle: Text('1.0.0+1'),
          ),
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('Termos de Serviço'),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
