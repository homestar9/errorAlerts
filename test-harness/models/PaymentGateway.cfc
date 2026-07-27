/**
 * PaymentGateway
 *
 * Fake payment gateway used by OrderService. Every method throws so the alert
 * email shows a stack that passes through more than one component.
 */
component singleton {

	/**
	 * charge
	 *
	 * Always throws a declined-card error.
	 *
	 * @amount     The amount to charge.
	 * @cardNumber The card number, only used in the detail text.
	 */
	function charge( required numeric amount, required string cardNumber ){
		throw(
			type    = "Harness.Payment.Declined",
			message = "Card declined by the payment gateway",
			detail  = "Gateway returned code 51 (insufficient funds) for a charge of $#arguments.amount#."
		);
	}

	/**
	 * refund
	 *
	 * Catches a low-level failure and throws a higher-level one that carries the
	 * original error, which is how most application code reports a wrapped
	 * failure.
	 *
	 * Lucee's throw() takes a `cause` argument, but Adobe's does not and rejects
	 * it while compiling, even on a branch that would never run. So the original
	 * error is carried in `extendedInfo` instead, which works everywhere.
	 *
	 * @transactionId The transaction to refund.
	 */
	function refund( required string transactionId ){
		try {
			throw(
				type    = "Harness.Payment.NetworkTimeout",
				message = "Timed out waiting for the gateway",
				detail  = "No response after 30 seconds."
			);
		} catch ( any e ) {
			throw(
				type         = "Harness.Payment.RefundFailed",
				message      = "Could not refund transaction #arguments.transactionId#",
				detail       = "The gateway call failed with: #e.message#",
				extendedInfo = serializeJSON( {
					"causeType"    : e.type,
					"causeMessage" : e.message,
					"causeDetail"  : e.detail
				} )
			);
		}
	}

}
