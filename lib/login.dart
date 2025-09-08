import 'imports.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback onLogin;
  final VoidCallback onGoToRegister;

  const LoginPage({super.key, required this.onLogin, required this.onGoToRegister});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool busy = false;

  Future<void> _login() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await Future.delayed(const Duration(milliseconds: 600));
      widget.onLogin();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            StyledTextField(controller: emailCtrl, hint: 'Email', keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 12),
            StyledTextField(controller: passCtrl, hint: 'Password', obscureText: true),
            const SizedBox(height: 20),
            StyledButton(label: busy ? 'Signing in…' : 'Sign in', onPressed: _login, icon: Icons.login),
            const SizedBox(height: 12),
            TextButton(
              onPressed: widget.onGoToRegister,
              child: const Text('Create an account'),
            ),
          ],
        ),
      ),
    );
  }
}
