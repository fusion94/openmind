class AccountController < ApplicationController
  # Be sure to include AuthenticationSystem in Application Controller instead
  include AuthenticatedSystem
  include OpenIdAuthentication

  # If you want "remember me" functionality, add this before_filter to Application Controller
  before_filter :login_from_cookie, :except => [:login]
  before_filter :login_required, :only => [:logout]
  cache_sweeper :allocations_sweeper, :only => [:login, :continue_openid]

  # say something nice, you goof!  something sweet.
  def index
    redirect_to(:action => 'signup') unless logged_in? || User.count > 0
  end

  def login
    return unless request.post?
    @login = params[:login] # needed to remember login info in login fails
    self.current_user = User.authenticate(params[:login], params[:password])
    if logged_in?
      logged_in
    else
      flash[:error] = "Login failed...please try again"
    end
  end

  def login_otp
    @login = params[:login] # needed to remember login info in login fails
    unless logged_in?
      self.current_user = User.authenticate_otp(params[:login], params[:password])
      if self.current_user
        logger.info "Current user is #{self.current_user.id}"
      else
        logger.info "current user is empty"
      end
    end
    if logged_in?
      # if a uri is specified, automatically navigate to it
      store_location(params[:target_uri]) if params[:target_uri]
      logged_in
    else
      if User.find_by_email(params[:login])
        flash[:error] = "Login failed...please try again"
        redirect_to :controller => '/account', :action => 'login'
      else
        flash[:error] = "It looks like you don't have an OpenMind account. Please request one."
        redirect_to new_user_request_path(:email => params[:login], :first_name => params[:first_name],
                                          :last_name => params[:last_name], :enterprise_name => params[:enterprise_name])
      end
    end
  end

  def external_login
    return unless request.post?
    trusted_sites = (APP_CONFIG['otp_trusted_sites'] || "")
    if Regexp.new(trusted_sites).match(request.remote_ip)
      self.current_user = User.authenticate(params[:login], params[:password])
      logger.info("External login from #{request.remote_ip} resulted in #{logged_in?}")
    else
      logger.warn("Request for external login from an untrusted site: #{request.remote_ip} is not in #{APP_CONFIG['otp_trusted_sites']}")
    end
    respond_to do |format|
      format.xml do
        if logged_in?
          render :xml => self.current_user.external_login_to_xml
        else
          render :nothing => true, :status => 404
        end
      end
    end
  end

  def login_openid
    return unless request.post?

    @openid_url = add_trailing_slash params[:openid_url]

    user = User.find_by_identity_url(@openid_url)
    if user.nil?
      flash[:error] = "No OpenMind user associated to this Open Id. Edit your user profile to update your Open Id."
      return
    end

    status = begin_openid_authentication(@openid_url, '/account/continue_openid')

    flash[:error] = case status
                      when :missing then
                        'Sorry, the OpenID is missing.'
                      when :failed then
                        'Sorry, the OpenID verification failed.'
                      when :timeout then
                        'Timed out.'
                      when :unknown then
                        'Not sure what happened.'
                    end
  end

  def continue_openid
    status = complete_openid_authentication

    case status
      when :missing then
        failed_login('Sorry, the OpenID server couldn\'t be found.')
      when :canceled then
        failed_login('OpenID verification was canceled.')
      when :failed then
        failed_login('Sorry, the OpenID verification failed.')
      when :unknown then
        failed_login('Not sure what happened.')
      when :success
        self.current_user = User.find_by_identity_url(openid_result[:identity_url])
        logged_in
    end
  end

  def activate
    flash.clear
    return if params[:id].nil? and params[:activation_code].nil?
    activator = params[:activation_code] || params[:id]
    @user = User.find_by_activation_code(activator)
    if @user
      if @user.activate
        redirect_to(:controller => '/account', :action => 'login')
        flash[:notice] = "Your account has been activated. Please login."
      else
        flash[:error] = "Unable to activate the account. Please check or enter manually."
      end
    else
      flash[:error] = "Unable to activate the account: no such activation code '#{activator}'."
    end
  end

  def signup
    @user = User.new(params[:user])
    return unless request.post?
    @user.save!
    self.current_user = @user
    redirect_back_or_default home_path
    flash[:notice] = "Thanks for signing up!"
  rescue ActiveRecord::RecordInvalid
    render :action => 'signup'
  end

  def logout
    #    self.current_user.forget_me if logged_in?
    #    cookies.delete :auth_token
    reset_session
    flash[:notice] = "You have been logged out."
    redirect_back_or_default(:controller => '/account', :action => 'login')
  end

  def change_password
    return unless request.post?
    @user = self.current_user
    if params[:user][:password] != params[:user][:password_confirmation]
      flash[:error] = "Password confirmation must match"
      render :action => 'change_password'
    elsif @user.authenticated?(params[:current_password])
      @user.update_attributes(params[:user])
      @user.update_attribute(:force_change_password, false)
      @user.save!
      flash[:notice] = "Password has been successfully changed."
      redirect_to home_path
    else
      flash[:error] = "Password authentication failed"
      render :action => 'change_password'
    end

  rescue ActiveRecord::RecordInvalid
    render :action => 'change_password'
  end

  private

  def failed_login(message)
    flash[:error] = message
    #      redirect_to(open_id_path(:login))
  end
end
