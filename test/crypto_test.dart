// Ibasho — tests del cifrado de punta a punta.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/crypto/backup.dart';
import 'package:ibasho/crypto/envelope.dart';
import 'package:ibasho/crypto/keys.dart';
import 'package:ibasho/crypto/mnemonic.dart';
import 'package:ibasho/crypto/wordlist.dart';

void main() {
  group('claves', () {
    test('un par nuevo va y vuelve por sus bytes', () {
      final keys = IdentityKeys.generate();
      final again = IdentityKeys.fromPrivateBytes(keys.privateBytes);
      expect(again, isNotNull);
      expect(again!.public.encoded, keys.public.encoded);
    });

    test('la publica cabe en lo que dejan las reglas', () {
      final keys = IdentityKeys.generate();
      expect(keys.public.encoded.length, greaterThanOrEqualTo(80));
      expect(keys.public.encoded.length, lessThanOrEqualTo(128));
    });

    test('las dos partes llegan al mismo secreto', () {
      final a = IdentityKeys.generate();
      final b = IdentityKeys.generate();
      expect(a.sharedSecret(b.public), b.sharedSecret(a.public));
    });

    test('una publica con basura no se acepta', () {
      expect(PublicKey.tryParse(null), isNull);
      expect(PublicKey.tryParse(''), isNull);
      expect(PublicKey.tryParse('no es base64 %%%'), isNull);
      expect(PublicKey.tryParse(base64.encode(List<int>.filled(65, 4))), isNull);
    });
  });

  group('sobres', () {
    test('quien esta en el sobre lo abre y quien no, no', () {
      final ana = IdentityKeys.generate();
      final luis = IdentityKeys.generate();
      final ajena = IdentityKeys.generate();

      final sobre = SealedEnvelope.seal(
        'nos vemos a las ocho',
        recipients: {'ana': ana.public, 'luis': luis.public},
      );

      expect(sobre.open('luis', luis), 'nos vemos a las ocho');
      expect(sobre.open('ana', ana), 'nos vemos a las ocho');
      // Ni con las claves de otro, ni diciendo ser otro.
      expect(sobre.open('ajena', ajena), isNull);
      expect(sobre.open('luis', ajena), isNull);
    });

    test('el texto cifrado no deja ver el original', () {
      final ana = IdentityKeys.generate();
      final sobre = SealedEnvelope.seal('contraseña', recipients: {'ana': ana.public});
      expect(sobre.ciphertext.contains('contra'), isFalse);
      expect(utf8.decode(base64.decode(sobre.ciphertext), allowMalformed: true)
          .contains('contraseña'), isFalse);
    });

    test('dos sobres iguales salen distintos', () {
      final ana = IdentityKeys.generate();
      final uno = SealedEnvelope.seal('hola', recipients: {'ana': ana.public});
      final dos = SealedEnvelope.seal('hola', recipients: {'ana': ana.public});
      expect(uno.ciphertext, isNot(dos.ciphertext));
      expect(uno.ephemeral, isNot(dos.ephemeral));
    });

    test('un sobre tocado no se abre a medias', () {
      final ana = IdentityKeys.generate();
      final sobre = SealedEnvelope.seal('hola', recipients: {'ana': ana.public});
      final bytes = base64.decode(sobre.ciphertext);
      bytes[bytes.length - 1] ^= 0x01;
      final tocado = SealedEnvelope(
        ephemeral: sobre.ephemeral,
        ciphertext: base64.encode(bytes),
        wraps: sobre.wraps,
      );
      expect(tocado.open('ana', ana), isNull);
    });

    test('va y vuelve por JSON', () {
      final ana = IdentityKeys.generate();
      final sobre = SealedEnvelope.seal('hola', recipients: {'ana': ana.public});
      final vuelta = SealedEnvelope.fromJson(sobre.toJson());
      expect(vuelta, isNotNull);
      expect(vuelta!.open('ana', ana), 'hola');
    });

    test('no se pasa del tope de destinatarios', () {
      final muchos = <String, PublicKey>{
        for (var i = 0; i <= maxEnvelopeRecipients; i++)
          'cuenta$i': IdentityKeys.generate().public,
      };
      expect(() => SealedEnvelope.seal('hola', recipients: muchos), throwsArgumentError);
      expect(() => SealedEnvelope.seal('hola', recipients: const {}), throwsArgumentError);
    });
  });

  group('frase de respaldo', () {
    test('doce palabras de la lista', () {
      final frase = generateMnemonic();
      expect(frase, hasLength(mnemonicWords));
      expect(frase.every(backupWordlist.contains), isTrue);
    });

    test('la frase va y vuelve', () {
      final entropia = Uint8List.fromList(
        List<int>.generate(mnemonicEntropyBytes, (i) => i * 7 + 3),
      );
      final frase = mnemonicFromEntropy(entropia);
      expect(entropyFromMnemonic(frase.join(' ')), entropia);
    });

    test('se teclea como se pueda', () {
      final frase = mnemonicFromEntropy(
        Uint8List.fromList(List<int>.filled(mnemonicEntropyBytes, 42)),
      );
      final maltratada = frase.map((w) => w.toUpperCase()).join('   ');
      expect(entropyFromMnemonic(maltratada), entropyFromMnemonic(frase.join(' ')));
      // Con cuatro letras basta: el prefijo identifica la palabra.
      final cortada = frase.map((w) => w.length > 4 ? w.substring(0, 4) : w).join(' ');
      expect(entropyFromMnemonic(cortada), entropyFromMnemonic(frase.join(' ')));
    });

    test('una palabra cambiada no cuela', () {
      final frase = generateMnemonic().toList();
      frase[3] = frase[3] == 'abeja' ? 'abeto' : 'abeja';
      try {
        entropyFromMnemonic(frase.join(' '));
        fail('la suma de comprobacion tendria que haber saltado');
      } on MnemonicError catch (e) {
        expect(e.failure, MnemonicFailure.checksum);
      }
    });

    test('dice donde esta el fallo', () {
      final frase = generateMnemonic().toList();
      frase[5] = 'zzzz';
      try {
        entropyFromMnemonic(frase.join(' '));
        fail('tendria que haber avisado de la palabra desconocida');
      } on MnemonicError catch (e) {
        expect(e.failure, MnemonicFailure.unknownWord);
        expect(e.index, 5);
        expect(e.word, 'zzzz');
      }
    });

    test('once palabras no son doce', () {
      final frase = generateMnemonic().take(11).join(' ');
      try {
        entropyFromMnemonic(frase);
        fail('tendria que haber contado las palabras');
      } on MnemonicError catch (e) {
        expect(e.failure, MnemonicFailure.wordCount);
      }
    });
  });

  group('respaldo de la clave', () {
    test('la frase correcta lo abre y otra no', () {
      final keys = IdentityKeys.generate();
      final frase = generateMnemonic();
      final respaldo = KeyBackup.wrap(keys, frase);

      final vuelta = respaldo.unwrap(frase);
      expect(vuelta, isNotNull);
      expect(vuelta!.public.encoded, keys.public.encoded);

      expect(respaldo.unwrap(generateMnemonic()), isNull);
    });

    test('va y vuelve por JSON', () {
      final keys = IdentityKeys.generate();
      final frase = generateMnemonic();
      final respaldo = KeyBackup.fromJson(KeyBackup.wrap(keys, frase).toJson());
      expect(respaldo, isNotNull);
      expect(respaldo!.unwrap(frase)!.public.encoded, keys.public.encoded);
    });

    test('cabe en lo que dejan las reglas', () {
      final respaldo = KeyBackup.wrap(IdentityKeys.generate(), generateMnemonic());
      expect(respaldo.salt.length, lessThanOrEqualTo(64));
      expect(respaldo.data.length, lessThanOrEqualTo(256));
    });
  });
}
