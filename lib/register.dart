import 'imports.dart';

class RegisterPage extends StatefulWidget {
  final VoidCallback onRegistered;

  const RegisterPage({super.key, required this.onRegistered});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool busy = false;

  Future<void> _register() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await Future.delayed(const Duration(milliseconds: 700));
      widget.onRegistered();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            StyledTextField(controller: nameCtrl, hint: 'Full name', keyboardType: TextInputType.name),
            const SizedBox(height: 12),
            StyledTextField(controller: emailCtrl, hint: 'Email', keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 12),
            StyledTextField(controller: passCtrl, hint: 'Password', obscureText: true),
            const SizedBox(height: 20),
            StyledButton(label: busy ? 'Creating…' : 'Create account', onPressed: _register, icon: Icons.person_add),
          ],
        ),
      ),
    );
  }
}
