import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/user_profile.dart';
import '../../../core/providers/user_profile_provider.dart';
import '../../../core/theme/app_theme.dart';

class EditProfileSheet extends ConsumerStatefulWidget {
  final UserProfile initialProfile;
  const EditProfileSheet({super.key, required this.initialProfile});

  @override
  ConsumerState<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<EditProfileSheet> {
  final _avatars = ['👦', '👧', '👨', '👩', '👱‍♂️', '👱‍♀️', '🧔', '👩‍🦰', '👨‍🦱', '👲', '🧕', '🧑‍🎤'];
  late String _selectedAvatar;
  late TextEditingController _nameCtrl;
  late TextEditingController _ageCtrl;
  late TextEditingController _weightCtrl;
  late TextEditingController _heightCtrl;

  @override
  void initState() {
    super.initState();
    _selectedAvatar = widget.initialProfile.avatar ?? '👦';
    _nameCtrl = TextEditingController(text: widget.initialProfile.name);
    _ageCtrl = TextEditingController(text: widget.initialProfile.age.toString());
    _weightCtrl = TextEditingController(text: widget.initialProfile.weight.toString());
    _heightCtrl = TextEditingController(text: widget.initialProfile.height.toString());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final updated = widget.initialProfile.copyWith(
      avatar: _selectedAvatar,
      name: _nameCtrl.text.trim().isEmpty ? 'Athlete' : _nameCtrl.text.trim(),
      age: int.tryParse(_ageCtrl.text) ?? widget.initialProfile.age,
      weight: double.tryParse(_weightCtrl.text) ?? widget.initialProfile.weight,
      height: double.tryParse(_heightCtrl.text) ?? widget.initialProfile.height,
    );
    ref.read(userProfileProvider.notifier).saveProfile(updated);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit Profile',
                style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            
            // Avatar Selection
            Text('Choose Avatar', style: GoogleFonts.outfit(color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            SizedBox(
              height: 60,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _avatars.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) {
                  final a = _avatars[i];
                  final isSel = a == _selectedAvatar;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedAvatar = a),
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSel ? AppTheme.primary : const Color(0xFF2A2A2A),
                          width: isSel ? 2 : 1,
                        ),
                      ),
                      child: Center(
                        child: Text(a, style: const TextStyle(fontSize: 32)),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // Form Fields
            _buildField('Name', _nameCtrl, TextInputType.name),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildField('Age', _ageCtrl, TextInputType.number)),
                const SizedBox(width: 16),
                Expanded(child: _buildField('Weight (kg)', _weightCtrl, TextInputType.number)),
                const SizedBox(width: 16),
                Expanded(child: _buildField('Height (cm)', _heightCtrl, TextInputType.number)),
              ],
            ),
            const SizedBox(height: 32),
            
            // Save Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Save Changes',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, TextInputType type) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.outfit(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: type,
          style: GoogleFonts.outfit(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppTheme.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.primary),
            ),
          ),
        ),
      ],
    );
  }
}
