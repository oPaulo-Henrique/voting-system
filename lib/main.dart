import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Imports do Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  runApp(const MyApp());
}

// --- MODELS ---

class PollOption {
  String text;
  int votes;
  PollOption(this.text, {this.votes = 0});

  Map<String, dynamic> toMap() => {'text': text, 'votes': votes};

  factory PollOption.fromMap(Map<String, dynamic> map) {
    return PollOption(map['text'], votes: map['votes'] ?? 0);
  }
}

class PollRoom {
  String code;
  String question;
  List<PollOption> options;
  bool isActive;
  List<String> votedUsers;

  PollRoom({
    required this.code,
    required this.question,
    required this.options,
    this.isActive = true,
    List<String>? votedUsers,
  }) : votedUsers = votedUsers ?? [];

  int get totalVotes => options.fold(0, (sum, opt) => sum + opt.votes);

  Map<String, dynamic> toMap() => {
    'code': code,
    'question': question,
    'isActive': isActive,
    'votedUsers': votedUsers,
    'options': options.map((o) => o.toMap()).toList(),
  };

  factory PollRoom.fromMap(Map<String, dynamic> map) {
    return PollRoom(
      code: map['code'],
      question: map['question'],
      isActive: map['isActive'] ?? true,
      votedUsers: List<String>.from(map['votedUsers'] ?? []),
      options: (map['options'] as List).map((o) => PollOption.fromMap(o)).toList(),
    );
  }
}

// --- STATE MANAGEMENT ---

class VotingAppState extends ChangeNotifier {
  List<PollRoom> rooms = [];
  
  User? get currentUser => FirebaseAuth.instance.currentUser;
  
  bool get isOrganizerAuthenticated => currentUser != null && !currentUser!.isAnonymous;
  
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  VotingAppState() {
    _auth.authStateChanges().listen((user) {
      notifyListeners();
    });

    _db.collection('rooms').snapshots().listen((snapshot) {
      rooms = snapshot.docs.map((doc) => PollRoom.fromMap(doc.data())).toList();
      notifyListeners();
    });
  }

  Future<void> signInGuest() async {
    if (currentUser == null) {
      try {
        await _auth.signInAnonymously();
      } catch (e) {
        debugPrint('Erro no login anônimo: $e');
      }
    }
  }

  Future<String?> loginOrganizer(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return 'Erro ao fazer login: Verifique suas credenciais.';
    } catch (e) {
      return 'Erro desconhecido.';
    }
  }

  Future<String?> registerOrganizer(String email, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return 'Erro ao registrar: ${e.message}';
    } catch (e) {
      return 'Erro desconhecido.';
    }
  }

  Future<void> logoutOrganizer() async {
    await _auth.signOut();
  }

  String createRoom(String question, List<String> optionTexts) {
    String code = (1000 + Random().nextInt(9000)).toString();
    List<PollOption> options = optionTexts
        .where((text) => text.trim().isNotEmpty)
        .map((text) => PollOption(text.trim()))
        .toList();
    
    PollRoom newRoom = PollRoom(code: code, question: question, options: options);
    _db.collection('rooms').doc(code).set(newRoom.toMap());
    
    return code;
  }

  void toggleRoomStatus(String code) {
    var room = getRoom(code, ignoreStatus: true);
    if (room != null) {
      _db.collection('rooms').doc(code).update({'isActive': !room.isActive});
    }
  }

  PollRoom? getRoom(String code, {bool ignoreStatus = false}) {
    try {
      return rooms.firstWhere((r) => r.code == code && (ignoreStatus || r.isActive));
    } catch (e) {
      return null;
    }
  }

  bool hasUserVoted(String roomCode) {
    var room = getRoom(roomCode);
    String? uid = currentUser?.uid;
    
    if (uid == null) return false;
    return room?.votedUsers.contains(uid) ?? false;
  }

  bool vote(String roomCode, int optionIndex) {
    var room = getRoom(roomCode);
    String? uid = currentUser?.uid;

    if (uid != null && room != null && room.isActive && !room.votedUsers.contains(uid)) {
      room.options[optionIndex].votes++;
      room.votedUsers.add(uid);
      
      _db.collection('rooms').doc(roomCode).update({
        'options': room.options.map((o) => o.toMap()).toList(),
        'votedUsers': room.votedUsers,
      });
      return true;
    }
    return false;
  }
}

// --- UI COMPONENTS ---

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => VotingAppState(),
      child: MaterialApp(
        title: 'VoteHub',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4F46E5),
            brightness: Brightness.light,
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
            ),
          ),
        ),
        home: const LandingPage(),
      ),
    );
  }
}

/// TELA INICIAL (Landing Page)
class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.how_to_vote_rounded, size: 80, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 24),
              Text(
                'VoteHub',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                      letterSpacing: -1,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Decisões rápidas, resultados em tempo real.',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const ParticipantPage()));
                      },
                      icon: const Icon(Icons.group_add_rounded),
                      label: const Text('ENTRAR EM UMA SALA', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      onPressed: () {
                        final appState = context.read<VotingAppState>();
                        if (appState.isOrganizerAuthenticated) {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const OrganizerDashboard()));
                        } else {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const AuthPage()));
                        }
                      },
                      icon: const Icon(Icons.space_dashboard_rounded, color: Colors.black87),
                      label: const Text('ÁREA DO ORGANIZADOR', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- TELA DE LOGIN / REGISTRO ORGANIZADOR ---
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isLogin = true; 

  void _submit() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) return;

    setState(() => _isLoading = true);
    
    var appState = context.read<VotingAppState>();
    String? errorMessage;

    if (_isLogin) {
      errorMessage = await appState.loginOrganizer(_emailController.text, _passwordController.text);
    } else {
      errorMessage = await appState.registerOrganizer(_emailController.text, _passwordController.text);
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
      
      if (errorMessage == null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const OrganizerDashboard()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage), behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isLogin ? 'Bem-vindo de volta' : 'Crie sua conta',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                Text(
                  _isLogin ? 'Faça login para gerenciar suas votações.' : 'Registre-se para criar novas salas de votação.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.email_outlined)),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Senha', prefixIcon: Icon(Icons.lock_outline)),
                ),
                const SizedBox(height: 32),
                _isLoading 
                  ? const Center(child: CircularProgressIndicator())
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _submit,
                        child: Text(_isLogin ? 'Entrar' : 'Registrar-se'),
                      ),
                    ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => _isLogin = !_isLogin),
                    child: Text(_isLogin ? 'Não tem uma conta? Crie aqui.' : 'Já possui conta? Faça login.'),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- PARTICIPANT PAGE ---
class ParticipantPage extends StatefulWidget {
  const ParticipantPage({super.key});

  @override
  State<ParticipantPage> createState() => _ParticipantPageState();
}

class _ParticipantPageState extends State<ParticipantPage> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  PollRoom? activeRoom;
  bool hasVoted = false;

  void _joinRoom(VotingAppState appState) async {
    if (_nameController.text.trim().isEmpty || _codeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha todos os campos.')));
      return;
    }

    await appState.signInGuest();

    var room = appState.getRoom(_codeController.text.trim());
    if (room != null) {
      setState(() {
        activeRoom = room;
        hasVoted = appState.hasUserVoted(room.code);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Código de sala inválido ou votação encerrada.'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<VotingAppState>();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Sala de Votação', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: activeRoom != null 
              ? _buildVoteView(appState) 
              : _buildJoinView(appState),
          ),
        ),
      ),
    );
  }

  Widget _buildJoinView(VotingAppState appState) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.sensor_door_outlined, size: 48, color: Colors.indigo),
            ),
            const SizedBox(height: 24),
            Text('Acessar Votação', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Insira seus dados para participar', style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 32),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Como quer ser chamado?'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(labelText: 'Código da Sala (Ex: 1234)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _joinRoom(appState),
                child: const Text('Entrar na Sala'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoteView(VotingAppState appState) {
    var currentRoom = appState.getRoom(activeRoom!.code);
    
    if (currentRoom == null) {
      return Card(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            children: [
              const Icon(Icons.lock_clock, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text('Votação Encerrada', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('O organizador finalizou esta sessão.', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              OutlinedButton(onPressed: () => setState(() => activeRoom = null), child: const Text('Voltar ao início'))
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
                  child: Text('SALA ${currentRoom.code}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
                const SizedBox(height: 24),
                Text(currentRoom.question, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 32),
                
                if (hasVoted) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12)),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green),
                        SizedBox(width: 8),
                        Text('Voto registrado com sucesso!', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Resultados parciais:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  ...List.generate(currentRoom.options.length, (index) {
                    final opt = currentRoom.options[index];
                    final percent = currentRoom.totalVotes == 0 ? 0.0 : opt.votes / currentRoom.totalVotes;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(opt.text, style: const TextStyle(fontWeight: FontWeight.w500)),
                              Text('${opt.votes} votos (${(percent * 100).toStringAsFixed(1)}%)', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: percent,
                              minHeight: 12,
                              backgroundColor: Colors.grey.shade200,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          )
                        ],
                      ),
                    );
                  }),
                ] else
                  ...List.generate(currentRoom.options.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.all(20),
                          alignment: Alignment.centerLeft,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          bool success = appState.vote(currentRoom.code, index);
                          if (success) setState(() => hasVoted = true);
                        },
                        child: Row(
                          children: [
                            Container(
                              width: 24, height: 24,
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade400)),
                            ),
                            const SizedBox(width: 16),
                            Expanded(child: Text(currentRoom.options[index].text, style: const TextStyle(fontSize: 16, color: Colors.black87))),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () => setState(() => activeRoom = null),
          icon: const Icon(Icons.exit_to_app),
          label: const Text('Sair da Sala'),
        )
      ],
    );
  }
}

// --- ORGANIZER DASHBOARD ---
class OrganizerDashboard extends StatefulWidget {
  const OrganizerDashboard({super.key});

  @override
  State<OrganizerDashboard> createState() => _OrganizerDashboardState();
}

class _OrganizerDashboardState extends State<OrganizerDashboard> {
  void _openRoomDetails(String code) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Consumer<VotingAppState>(
          builder: (context, appState, child) {
            var room = appState.getRoom(code, ignoreStatus: true);
            if (room == null) return const AlertDialog(content: Text('Sala não encontrada.'));

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500, maxHeight: 650),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Resultados em tempo real', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black54)),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(), 
                          )
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.sensor_door_outlined, color: Colors.indigo.shade300),
                                const SizedBox(width: 8),
                                Text('SALA ${room.code}', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.indigo)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(room.question, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 32),
                            ...room.options.map((opt) {
                              final percent = room.totalVotes == 0 ? 0.0 : opt.votes / room.totalVotes;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 24.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(child: Text(opt.text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                                        Text('${opt.votes} votos', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: percent,
                                        minHeight: 16,
                                        backgroundColor: Colors.grey.shade100,
                                        color: room.isActive ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text('${(percent * 100).toStringAsFixed(1)}%', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(24.0),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                        border: Border(top: BorderSide(color: Colors.grey.shade200))
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total de Votos', style: TextStyle(fontWeight: FontWeight.w600)),
                              Text('${room.totalVotes}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                side: BorderSide(color: room.isActive ? Colors.red.shade200 : Colors.green.shade200),
                                foregroundColor: room.isActive ? Colors.red : Colors.green,
                              ),
                              onPressed: () => appState.toggleRoomStatus(room.code),
                              icon: Icon(room.isActive ? Icons.lock_outline : Icons.lock_open_outlined),
                              label: Text(room.isActive ? 'Encerrar Votação' : 'Reabrir Votação', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  void _openCreateRoomModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const CreateRoomModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<VotingAppState>();

    if (!appState.isOrganizerAuthenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Dashboard', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout, color: Colors.black87),
            onPressed: () {
              appState.logoutOrganizer();
              Navigator.pushAndRemoveUntil(
                context, 
                MaterialPageRoute(builder: (context) => const LandingPage()), 
                (route) => false
              );
            },
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateRoomModal,
        icon: const Icon(Icons.add_chart, color: Colors.white),
        label: const Text('Nova Votação', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.primary,
        elevation: 4,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 24.0),
                  child: Text('Suas Salas de Votação', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ),
                if (appState.rooms.isEmpty)
                   Center(
                    child: Padding(
                      padding: const EdgeInsets.all(48.0),
                      child: Column(
                        children: [
                          Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text('Você ainda não possui salas criadas.', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                        ],
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: appState.rooms.reversed.map((room) {
                      return ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 380),
                        child: _buildRoomSummaryCard(room),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoomSummaryCard(PollRoom room) {
    return Card(
      margin: EdgeInsets.zero,
      color: Colors.white,
      clipBehavior: Clip.antiAlias, 
      child: InkWell(
        onTap: () => _openRoomDetails(room.code),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: room.isActive ? Colors.green.shade50 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      room.isActive ? 'ATIVA' : 'ENCERRADA',
                      style: TextStyle(color: room.isActive ? Colors.green.shade700 : Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text('CÓD: ${room.code}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade300, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 16),
              Text(room.question, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${room.totalVotes} VOTOS', style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.bold)),
                  const Row(
                    children: [
                      Text('Ver Resultados', style: TextStyle(color: Colors.indigo, fontSize: 13, fontWeight: FontWeight.w600)),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios, size: 12, color: Colors.indigo),
                    ],
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

// --- MODAL DE CRIAR NOVA VOTAÇÃO ---
class CreateRoomModal extends StatefulWidget {
  const CreateRoomModal({super.key});

  @override
  State<CreateRoomModal> createState() => _CreateRoomModalState();
}

class _CreateRoomModalState extends State<CreateRoomModal> {
  final _questionController = TextEditingController();
  final List<TextEditingController> _optionsControllers = [TextEditingController(), TextEditingController()];

  @override
  void dispose() {
    _questionController.dispose();
    for (var c in _optionsControllers) { c.dispose(); }
    super.dispose();
  }

  void _addOption() {
    setState(() {
      _optionsControllers.add(TextEditingController());
    });
  }

  void _removeOption(int index) {
    if (_optionsControllers.length > 2) {
      setState(() {
        _optionsControllers[index].dispose();
        _optionsControllers.removeAt(index);
      });
    }
  }

  void _createRoom(BuildContext context) {
    if (_questionController.text.isEmpty || _optionsControllers.any((c) => c.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha a pergunta e todas as opções.')));
      return;
    }

    var appState = Provider.of<VotingAppState>(context, listen: false);
    
    List<String> optionsText = _optionsControllers.map((c) => c.text).toList();
    appState.createRoom(_questionController.text, optionsText);
    
    Navigator.of(context).pop();
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sala criada com sucesso!'), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header do Form
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.add_box_outlined, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text('Criar Nova Votação', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop())
                ],
              ),
            ),
            const Divider(height: 1),
            
            // Corpo do formulário
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _questionController,
                      decoration: const InputDecoration(labelText: 'Qual é a pergunta?'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 24),
                    const Text('Opções de Resposta', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    ...List.generate(_optionsControllers.length, (index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _optionsControllers[index],
                                decoration: InputDecoration(
                                  labelText: 'Opção ${index + 1}',
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                              ),
                            ),
                            if (_optionsControllers.length > 2)
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                onPressed: () => _removeOption(index),
                              )
                          ],
                        ),
                      );
                    }),
                    TextButton.icon(
                      onPressed: _addOption,
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar mais uma opção'),
                    ),
                  ],
                ),
              ),
            ),
            
            // Footer do Form (Botões)
            Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                border: Border(top: BorderSide(color: Colors.grey.shade200))
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 16),
                  FilledButton(
                    onPressed: () => _createRoom(context),
                    child: const Text('GERAR SALA E COMPARTILHAR CÓDIGO'),
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