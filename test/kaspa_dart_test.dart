import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:kaspa_dart/kaspa/kaspa.dart';

import 'package:kaspa_dart/kaspa_dart.dart' as kaspa;

import 'config.dart';

void main() {
  test("create account", () {
    print("## create account");
    final seedHex = kaspa.mnemonicToSeedHex(testWordsFiscal);

    final hd =
        kaspa.HdWallet.forSeedHex(seedHex, type: kaspa.HdWalletType.schnorr);

    final pair = hd.deriveKeyPair(typeIndex: 0, index: 0);
    print("privateKey: ${HEX.encode(pair.privateKey)}");
    print("publicKey:  ${HEX.encode(pair.publicKey)}");

    final words = kaspa.bytesToWords(([0] + pair.publicKey).asUint8List());
    final data = kaspa.Bech32(AddressPrefix.kaspa.toString(), words);
    final address = kaspa.bech32.encode(data);
    print("address: $address");
  });

  test("sign transaction", () async {
    print("##sign transaction");

    const signOnly = true;
    final toAddress = Address.decodeAddress(testToAddress);
    final amountRaw = BigInt.from(11000000); // 0.11 KAS

    final seedHex = kaspa.mnemonicToSeedHex(testWordsFiscal);

    final hd = HdWallet.forSeedHex(seedHex, type: HdWalletType.schnorr);
    final pair = hd.deriveKeyPair(typeIndex: 0, index: 0);

    final words = kaspa.bytesToWords(([0] + pair.publicKey).asUint8List());
    final data = kaspa.Bech32('kaspa', words);
    final encoded = kaspa.bech32.encode(data);
    final changeAddress = Address.decodeAddress(encoded);

    final testUtxos = jsonDecode(utxoJsonString) as List;
    final spendableUtxos = <Utxo>[];
    for (var value in testUtxos) {
      final utxo = Utxo.fromJson(
        value,
      );
      spendableUtxos.add(utxo);
    }
    final fee = BigInt.from(spendableUtxos.length) * kFeePerInput;

    final sendTx = kaspa.SendTx(
      uri: KaspaUri(
        address: toAddress,
        amount: Amount.raw(amountRaw),
      ),
      amountRaw: amountRaw,
      utxos: spendableUtxos,
      fee: fee,
    );
    final txBuilder = kaspa.TransactionBuilder(utxos: spendableUtxos);
    final unSignTx = txBuilder.createUnsignedTransaction(
      toAddress: sendTx.toAddress,
      amount: sendTx.amount,
      changeAddress: changeAddress,
    );
    const hashType = SigHashType.sigHashAll;
    final reusedValues = SighashReusedValues();

    // Sign all inputs
    for (int index = 0; index < unSignTx.inputs.length; ++index) {
      final input = unSignTx.inputs[index];

      final hash = kaspa.calculateSignatureHashSchnorr(
        tx: unSignTx,
        inputIndex: index,
        hashType: hashType,
        sighashReusedValues: reusedValues,
      );

      final signature =
          await kaspa.KaspaUtil.computeSignDataSchnorr(hash, pair.privateKey);

      final signatureScript =
          [signature.length + 1] + signature + [hashType.raw];
      input.signatureScript.setAll(0, signatureScript);
    }

    final rpcTx = kaspa.RpcTransaction(
      version: unSignTx.version,
      inputs: unSignTx.inputs.map(
        (input) => kaspa.RpcTransactionInput(
          previousOutpoint: input.previousOutpoint.toRpc(),
          signatureScript: kaspa.bytesToHex(input.signatureScript),
          sequence: input.sequence,
          sigOpCount: input.sigOpCount,
        ),
      ),
      outputs: unSignTx.outputs.map(
        (output) => kaspa.RpcTransactionOutput(
          amount: output.value,
          scriptPublicKey: output.scriptPublicKey.toRpc(),
        ),
      ),
      lockTime: unSignTx.lockTime,
      subnetworkId: unSignTx.subnetworkId.hex,
      gas: unSignTx.gas,
      payload: unSignTx.payload?.hex,
    );

    print(
        "from address:\n$encoded \nsend to:\n$toAddress\nchange to:\n${changeAddress.encoded}");

    if (signOnly) {
      final message = kaspa.KaspadMessage(
        submitTransactionRequest: kaspa.SubmitTransactionRequestMessage(
          transaction: rpcTx,
          allowOrphan: false,
        ),
      );
      print("signed output\n${message.writeToJson()}");
    } else {
      final client = KaspaClient.url('node.kaspium.io', isSecure: true);

      final txId = await client.submitTransaction(rpcTx);

      print("txId $txId");
      print("check detail on https://explorer.kaspa.org/txs/$txId");
    }
  });
}
