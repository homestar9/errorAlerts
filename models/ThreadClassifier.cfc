/**
 * ThreadClassifier
 *
 * Identifies threads that ColdBox's async proxies run on, such as scheduled
 * tasks and futures. ColdBox's BaseProxy copies the request that created the
 * proxy into those threads, so their cgi, url, and request context describe an
 * unrelated earlier request. PayloadBuilder and CaptureService ask this
 * component before they read any request data.
 *
 * Each engine marks these threads differently:
 * - Adobe: BaseProxy calls FusionContext.setAsyncThread( true ). cfthread does
 *   not set the flag, but it inherits it through FusionContext.clone().
 * - Lucee: JavaProxy creates a dummy page context with a dummy request that
 *   reports method GET and host localhost.
 * - BoxLang: runThreadInContext() wraps the thread in a ThreadBoxContext.
 *
 * cfthread is checked first on every engine so it keeps its own
 * classification. The JDK's default executor thread names are a fallback for
 * an engine whose flag cannot be read. Every check returns false on failure,
 * so a real request is never reported as an async thread.
 */
component singleton accessors="true" {

	/**
	 * init
	 *
	 * Sets the patterns used to recognize threads and task frames.
	 */
	function init(){
		// ColdBox passes no ThreadFactory, so the JDK names its executor threads.
		variables.EXECUTOR_NAME_PATTERN = "^(pool-[0-9]+-thread-[0-9]+|ForkJoinPool(\.commonPool|-[0-9]+)-worker-[0-9]+)$";

		// Templates that are on the stack while a ColdBox scheduled task runs.
		variables.TASK_TEMPLATES = [
			"/system/async/tasks/ScheduledTask.cfc",
			"/system/web/tasks/ColdBoxScheduledTask.cfc"
		];

		// Limit the search on very large call stacks.
		variables.MAX_SCAN_FRAMES = 200;

		return this;
	}

	/**
	 * isAsyncThread
	 *
	 * Returns true when the current thread runs a ColdBox async proxy, so its
	 * request data was copied from another request. Returns false for request
	 * threads, cfthread, and whenever a check fails. Never throws.
	 */
	boolean function isAsyncThread(){
		try {
			if ( isCfThread() ) {
				return false;
			}

			var engine = engineName();
			if ( engine == "adobe" && adobeAsyncFlag() ) {
				return true;
			}
			if ( engine == "lucee" && luceeDummyContext() ) {
				return true;
			}
			if ( engine == "boxlang" && boxLangThreadContext() ) {
				return true;
			}

			return reFind( variables.EXECUTOR_NAME_PATTERN, threadName() ) > 0;
		} catch ( any e ) {
			return false;
		}
	}

	/**
	 * hasScheduledTaskFrame
	 *
	 * Returns true when a ColdBox scheduled task frame is on the live call stack
	 * or in the given exception frames. A failing task normally logs from inside
	 * ScheduledTask.run(), so the live stack shows it. An error that escapes
	 * run() reaches BaseProxy after that frame has returned, so the exception's
	 * own frames are checked as well. Never throws.
	 *
	 * @tagContext The raw tagContext array of the exception being reported, if any.
	 */
	boolean function hasScheduledTaskFrame( array tagContext = [] ){
		try {
			var templates = [];
			for ( var frame in arguments.tagContext ) {
				if ( ( isStruct( frame ) || isObject( frame ) ) && structKeyExists( frame, "template" ) ) {
					templates.append( toString( frame.template ) );
				}
			}
			if ( containsTaskTemplate( templates ) ) {
				return true;
			}
			return containsTaskTemplate( liveStackTemplates() );
		} catch ( any e ) {
			return false;
		}
	}

	/**
	 * threadName
	 *
	 * Returns the current Java thread name, or an empty string when it cannot
	 * be read. The name connects an alert to engine log lines.
	 */
	string function threadName(){
		try {
			return currentThreadName();
		} catch ( any e ) {
			return "";
		}
	}

	/**
	 * containsTaskTemplate
	 *
	 * Returns true when any template path ends with a scheduled task template.
	 * The check ignores the folder ColdBox is installed in.
	 *
	 * @templates Template paths to check.
	 */
	private boolean function containsTaskTemplate( required array templates ){
		var limit = min( arguments.templates.len(), variables.MAX_SCAN_FRAMES );

		for ( var i = 1; i <= limit; i++ ) {
			var path = arguments.templates[ i ].replace( "\", "/", "all" );
			for ( var marker in variables.TASK_TEMPLATES ) {
				if ( path.len() >= marker.len() && path.right( marker.len() ) == marker ) {
					return true;
				}
			}
		}

		return false;
	}

	/**
	 * engineName
	 *
	 * Returns "boxlang", "lucee", "adobe", or an empty string. Uses the same
	 * checks as ColdBox's BaseProxy. BoxLang and Lucee also define
	 * server.coldfusion, so their keys are checked first. The result is cached.
	 */
	private string function engineName(){
		if ( variables.keyExists( "cachedEngineName" ) ) {
			return variables.cachedEngineName;
		}

		var name = "";
		if ( server.keyExists( "boxlang" ) ) {
			name = "boxlang";
		} else if ( server.keyExists( "lucee" ) ) {
			name = "lucee";
		} else if (
			server.keyExists( "coldfusion" )
			&& server.coldfusion.keyExists( "productName" )
			&& server.coldfusion.productName.findNoCase( "ColdFusion" )
		) {
			name = "adobe";
		}

		variables.cachedEngineName = name;
		return name;
	}

	/**
	 * isCfThread
	 *
	 * Returns true inside a cfthread. Adobe names cfthread threads cfthread-N,
	 * as does Lucee, and BoxLang uses BL-Thread-. Adobe's isUnderCFThread()
	 * covers a renamed thread.
	 */
	private boolean function isCfThread(){
		var name = threadName();
		if ( name.findNoCase( "cfthread-" ) == 1 || name.find( "BL-Thread-" ) == 1 ) {
			return true;
		}

		if ( engineName() == "adobe" ) {
			try {
				return getPageContext().isUnderCFThread();
			} catch ( any e ) {
			}
		}

		return false;
	}

	/**
	 * adobeAsyncFlag
	 *
	 * Returns Adobe's FusionContext async flag, which ColdBox's BaseProxy sets
	 * for every thread it runs a task on. Adobe's runAsync() sets it as well.
	 * Returns false when there is no current FusionContext.
	 */
	private boolean function adobeAsyncFlag(){
		try {
			var current = createObject( "java", "coldfusion.filter.FusionContext" ).getCurrent();
			return !isNull( current ) && current.isAsyncThread();
		} catch ( any e ) {
			return false;
		}
	}

	/**
	 * luceeDummyContext
	 *
	 * Returns true when Lucee runs the current code on a dummy page context.
	 * Lucee builds one when a Java executor thread calls a CFC through a
	 * dynamic proxy. Lucee 6 reports it with isDummy(). Lucee 5 has no such
	 * method, so check for its dummy request with no parent page context
	 * instead.
	 */
	private boolean function luceeDummyContext(){
		try {
			var pageContext = getPageContext();

			try {
				return pageContext.isDummy();
			} catch ( any e ) {
				// Lucee 5 has no isDummy(). Continue with its dummy request.
			}

			var servletRequest = pageContext.getHttpServletRequest();
			try {
				servletRequest = servletRequest.getOriginalRequest();
			} catch ( any e ) {
			}

			return servletRequest.getClass().getName() == "lucee.runtime.net.http.HttpServletRequestDummy"
			&& isNull( pageContext.getParentPageContext() );
		} catch ( any e ) {
			return false;
		}
	}

	/**
	 * boxLangThreadContext
	 *
	 * Returns true when BoxLang runs the current code inside a ThreadBoxContext,
	 * which runThreadInContext() creates for ColdBox's async proxies. A cfthread
	 * context found first returns false, so a cfthread started inside a task
	 * stays a cfthread.
	 */
	private boolean function boxLangThreadContext(){
		try {
			var context = getBoxContext();

			for ( var depth = 1; depth <= 50 && !isNull( context ); depth++ ) {
				var className = context.getClass().getName();
				if ( className == "ortus.boxlang.runtime.context.ThreadComponentBoxContext" ) {
					return false;
				}
				if ( className == "ortus.boxlang.runtime.context.ThreadBoxContext" ) {
					return true;
				}
				if ( !context.hasParent() ) {
					break;
				}
				context = context.getParent();
			}
		} catch ( any e ) {
		}

		return false;
	}

	/**
	 * currentThreadName
	 *
	 * Reads the current Java thread name. A separate method, so tests can name
	 * the thread without starting one.
	 */
	private string function currentThreadName(){
		return createObject( "java", "java.lang.Thread" ).currentThread().getName();
	}

	/**
	 * liveStackTemplates
	 *
	 * Returns the template path of each frame on the live CFML call stack.
	 * A separate method, so tests can supply a stack.
	 */
	private array function liveStackTemplates(){
		var templates = [];

		try {
			for ( var frame in callStackGet() ) {
				if ( structKeyExists( frame, "template" ) ) {
					templates.append( toString( frame.template ) );
				}
			}
		} catch ( any e ) {
		}

		return templates;
	}

}
