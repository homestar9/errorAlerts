/**
 * Tests email creation, subjects, delivery modes, and failure handling.
 */
component extends="tests.resources.BaseUnitSpec" {

	/**
	 * run
	 *
	 * Defines EmailNotifier unit tests.
	 */
	function run(){
		describe( "EmailNotifier", function(){
			beforeEach( function(){
				settings = defaultSettings();
				captured = {};

				mailStub        = createStub();
				mailStub.$( "hasErrors", false );
				mailStub.$( "getResultMessages", [] );
				mailServiceStub = createStub();
				mailServiceStub.$( "newMail" ).$callback( function(){
					captured = arguments;
					return mailStub;
				} );
				mailServiceStub.$( "send", mailStub );
				mailServiceStub.$( "queue", "task-id" );

				rendererStub = createStub();
				rendererStub.$( "renderError", "<p>error body</p>" );
				rendererStub.$( "renderDigest", "<p>digest body</p>" );

				notifier = prepareMock( new errorAlerts.models.notifiers.EmailNotifier() );
				notifier.$property( propertyName = "settings", mock = settings );
				notifier.$property( propertyName = "renderer", mock = rendererStub );
				notifier.$property( propertyName = "mailService", mock = mailServiceStub );
			} );

			it( "builds the mail with the configured addresses and an html body", function(){
				notifier.sendNotification( newErrorPayload() );

				expect( captured.to ).toBe( "alerts@example.com" );
				expect( captured.from ).toBe( "harness@example.com" );
				expect( captured.type ).toBe( "html" );
				expect( captured.body ).toBe( "<p>error body</p>" );
				expect( captured.subject ).toInclude( "[Harness]" );
				expect( captured.subject ).toInclude( "ERROR" );
				expect( captured.subject ).toInclude( "Order save failed" );
			} );

			it( "falls back to `to` when `from` is blank", function(){
				settings.from = "";
				notifier.sendNotification( newErrorPayload() );
				expect( captured.from ).toBe( "alerts@example.com" );
			} );

			it( "falls back to the app name when the subject prefix is blank", function(){
				settings.subjectPrefix = "";
				notifier.sendNotification( newErrorPayload() );
				expect( captured.subject ).toInclude( "[StubApp]" );
			} );

			it( "queues by default", function(){
				settings.deliveryMode = "queue";
				notifier.sendNotification( newErrorPayload() );
				expect( mailServiceStub.$count( "queue" ) ).toBe( 1 );
				expect( mailServiceStub.$count( "send" ) ).toBe( 0 );
			} );

			it( "sends synchronously when deliveryMode is send", function(){
				settings.deliveryMode = "send";
				notifier.sendNotification( newErrorPayload() );
				expect( mailServiceStub.$count( "send" ) ).toBe( 1 );
				expect( mailServiceStub.$count( "queue" ) ).toBe( 0 );
			} );

			it( "renders digests with the digest renderer and subject", function(){
				notifier.sendNotification( newDigestPayload() );
				expect( captured.body ).toBe( "<p>digest body</p>" );
				expect( captured.subject ).toInclude( "DIGEST" );
				expect( captured.subject ).toInclude( "97" );
			} );

			it( "sends nothing when `to` is blank", function(){
				settings.to = "";
				expect( function(){
					notifier.sendNotification( newErrorPayload() );
				} ).notToThrow();
				expect( mailServiceStub.$count( "newMail" ) ).toBe( 0, "no mail object is created" );
			} );

			it( "throws DeliveryFailed when the mail cannot be built, so CaptureService can retry", function(){
				var brokenMailService = createStub();
				brokenMailService.$(
					method         = "newMail",
					throwException = true,
					throwType      = "MailDown",
					throwMessage   = "smtp exploded"
				);
				notifier.$property( propertyName = "mailService", mock = brokenMailService );

				expect( function(){
					notifier.sendNotification( newErrorPayload() );
				} ).toThrow( type = "errorAlerts.DeliveryFailed", regex = "smtp exploded" );
			} );

			it( "throws DeliveryFailed when rendering fails", function(){
				rendererStub.$(
					method         = "renderError",
					throwException = true,
					throwType      = "RenderDown",
					throwMessage   = "render exploded"
				);

				expect( function(){
					notifier.sendNotification( newErrorPayload() );
				} ).toThrow( type = "errorAlerts.DeliveryFailed" );
			} );

			it( "throws DeliveryFailed when queueing fails", function(){
				settings.deliveryMode = "queue";
				mailServiceStub.$(
					method         = "queue",
					throwException = true,
					throwType      = "QueueDown",
					throwMessage   = "queue exploded"
				);

				expect( function(){
					notifier.sendNotification( newErrorPayload() );
				} ).toThrow( type = "errorAlerts.DeliveryFailed" );
			} );

			it( "throws DeliveryFailed when send mode records a failed send", function(){
				/* cbmailservices' send() never throws. It records the failure on the
				 * mail object and logs it under an ignored category. */
				settings.deliveryMode = "send";
				mailStub.$( "hasErrors", true );
				mailStub.$( "getResultMessages", [ "Error sending mail. connection refused" ] );

				expect( function(){
					notifier.sendNotification( newErrorPayload() );
				} ).toThrow( type = "errorAlerts.DeliveryFailed", regex = "connection refused" );
			} );

			it( "caps the failure detail it throws", function(){
				settings.deliveryMode = "send";
				mailStub.$( "hasErrors", true );
				mailStub.$( "getResultMessages", [ repeatString( "x", 5000 ) ] );

				var thrown = {};
				try {
					notifier.sendNotification( newErrorPayload() );
				} catch ( any e ) {
					thrown = e;
				}
				expect( thrown.type ?: "" ).toBe( "errorAlerts.DeliveryFailed" );
				expect( len( thrown.detail ) ).toBeLTE( 500 );
			} );

			it( "does not throw when send mode records no failure", function(){
				settings.deliveryMode = "send";
				expect( function(){
					notifier.sendNotification( newErrorPayload() );
				} ).notToThrow();
				expect( mailStub.$count( "hasErrors" ) ).toBe( 1 );
			} );

			it( "does not read send results in queue mode", function(){
				settings.deliveryMode = "queue";
				notifier.sendNotification( newErrorPayload() );
				expect( mailStub.$count( "hasErrors" ) ).toBe( 0, "a queued mail has no send result yet" );
			} );
		} );
	}

	/**
	 * newErrorPayload
	 *
	 * Builds a small error payload for email tests.
	 */
	private struct function newErrorPayload(){
		return {
			type          : "error",
			severity      : "ERROR",
			category      : "app.orders",
			message       : "Order save failed",
			timestamp     : now(),
			appName       : "StubApp",
			environment   : "production",
			moduleVersion : "9.9.9",
			signature     : "sig-abc",
			occurrence    : 1,
			maxPerWindow  : 3,
			windowSeconds : 600,
			exception     : {},
			request       : {},
			rc            : {},
			extraInfo     : ""
		};
	}

	/**
	 * newDigestPayload
	 *
	 * Builds a small digest payload for email tests.
	 */
	private struct function newDigestPayload(){
		return {
			type            : "digest",
			severity        : "ERROR",
			signature       : "sig-abc",
			category        : "app.orders",
			message         : "Order save failed",
			totalCount      : 100,
			sentCount       : 3,
			suppressedCount : 97,
			firstSeen       : now(),
			lastSeen        : now(),
			windowSeconds   : 600,
			appName         : "StubApp",
			environment     : "production",
			moduleVersion   : "9.9.9"
		};
	}

}
