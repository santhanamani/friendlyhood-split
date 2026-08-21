import 'package:flutter/services.dart';

class UpiPaymentResult {
  const UpiPaymentResult({
    required this.status,
    required this.reference,
    required this.transactionId,
    required this.responseCode,
  });

  final String status;
  final String reference;
  final String transactionId;
  final String responseCode;

  bool get canCreatePendingDeposit =>
      status == 'success' || status == 'submitted';
  bool get wasCancelled => status == 'cancelled';

  factory UpiPaymentResult.fromMap(Map<Object?, Object?> value) =>
      UpiPaymentResult(
        status: '${value['status'] ?? 'unknown'}'.toLowerCase(),
        reference: '${value['reference'] ?? ''}',
        transactionId: '${value['transactionId'] ?? ''}',
        responseCode: '${value['responseCode'] ?? ''}',
      );
}

class UpiPaymentService {
  static const _channel = MethodChannel('com.friendlyhood.split/upi_payment');

  Future<UpiPaymentResult> pay({
    required String payeeUpiId,
    required String payeeName,
    required double amount,
    required String transactionReference,
    required String description,
  }) async {
    final response = await _channel.invokeMapMethod<Object?, Object?>('pay', {
      'payeeUpiId': payeeUpiId,
      'payeeName': payeeName,
      'amount': amount.toStringAsFixed(2),
      'transactionReference': transactionReference,
      'description': description,
      'currency': 'INR',
    });
    return UpiPaymentResult.fromMap(response ?? const {});
  }
}
