/**
 * OrderService
 *
 * Provides realistic service failures for the Trigger handler.
 * The resulting stacks pass through several application components.
 */
component singleton {

	property name="gateway" inject="PaymentGateway";

	/**
	 * placeOrder
	 *
	 * Fails inside PaymentGateway, two components below the handler.
	 *
	 * @customerId The customer placing the order.
	 * @total      The order total.
	 */
	function placeOrder( required string customerId, numeric total = 149.99 ){
		validateCustomer( arguments.customerId );
		return gateway.charge( amount = arguments.total, cardNumber = "4111111111111111" );
	}

	/**
	 * cancelOrder
	 *
	 * Fails in PaymentGateway.refund(), which wraps a lower-level error.
	 *
	 * @orderId The order to cancel.
	 */
	function cancelOrder( required string orderId ){
		return gateway.refund( transactionId = "txn-#arguments.orderId#" );
	}

	/**
	 * readMissingSetting
	 *
	 * Reads a variable that was never set, so the engine throws its own
	 * undefined-variable error rather than a thrown one.
	 */
	function readMissingSetting(){
		return variables.settingThatWasNeverSet;
	}

	/**
	 * divide
	 *
	 * Divides two numbers so callers can pass a zero divisor.
	 *
	 * @top    The numerator.
	 * @bottom The denominator.
	 */
	function divide( required numeric top, required numeric bottom ){
		return arguments.top / arguments.bottom;
	}

	/**
	 * applyDiscount
	 *
	 * Requires a numeric percent, so passing text throws a type error.
	 *
	 * @total   The order total.
	 * @percent The discount percent.
	 */
	numeric function applyDiscount( required numeric total, required numeric percent ){
		return arguments.total - ( arguments.total * ( arguments.percent / 100 ) );
	}

	/**
	 * lineItem
	 *
	 * Reads a line item by position without checking the array length.
	 *
	 * @position Which line item to read.
	 */
	function lineItem( required numeric position ){
		var items = [ "widget", "gadget" ];
		return items[ arguments.position ];
	}

	/**
	 * findCustomer
	 *
	 * Returns nothing, so calling a method on the result throws.
	 *
	 * @customerId The customer to look up.
	 */
	function findCustomer( required string customerId ){
		return;
	}

	/**
	 * validateCustomer
	 *
	 * Throws when the id is blank. Adds one more frame to the stack.
	 *
	 * @customerId The customer id to check.
	 */
	private void function validateCustomer( required string customerId ){
		if ( !arguments.customerId.trim().len() ) {
			throw( type = "Harness.Order.InvalidCustomer", message = "Customer id is required" );
		}
	}

}
