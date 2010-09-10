# Redmine - project management software
# Copyright (C) 2006-2008  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

class IssuesController < ApplicationController
  menu_item :new_issue, :only => [:new, :create]
  default_search_scope :issues
  
  before_filter :find_issue, :only => [:show, :edit, :update]
  before_filter :find_issues, :only => [:bulk_edit, :bulk_update, :move, :perform_move, :destroy]
  before_filter :find_project, :only => [:new, :create]
  before_filter :authorize, :except => [:index]
  before_filter :find_optional_project, :only => [:index]
  before_filter :check_for_default_issue_status, :only => [:new, :create]
  before_filter :build_new_issue_from_params, :only => [:new, :create]
  accept_key_auth :index, :show

  rescue_from Query::StatementInvalid, :with => :query_statement_invalid
  
  helper :journals
  helper :projects
  include ProjectsHelper   
  helper :custom_fields
  include CustomFieldsHelper
  helper :issue_relations
  include IssueRelationsHelper
  helper :watchers
  include WatchersHelper
  helper :attachments
  include AttachmentsHelper
  helper :queries
  include QueriesHelper
  helper :sort
  include SortHelper
  include IssuesHelper
  helper :timelog
  helper :gantt
  include Redmine::Export::PDF

  verify :method => [:post, :delete],
         :only => :destroy,
         :render => { :nothing => true, :status => :method_not_allowed }

  verify :method => :post, :only => :create, :render => {:nothing => true, :status => :method_not_allowed }
  verify :method => :post, :only => :bulk_update, :render => {:nothing => true, :status => :method_not_allowed }
  verify :method => :put, :only => :update, :render => {:nothing => true, :status => :method_not_allowed }
  
  def index
    retrieve_query
    sort_init(@query.sort_criteria.empty? ? [['id', 'desc']] : @query.sort_criteria)
    sort_update(@query.sortable_columns)
    
    if @query.valid?
      limit = case params[:format]
      when 'csv', 'pdf'
        Setting.issues_export_limit.to_i
      when 'atom'
        Setting.feeds_limit.to_i
      else
        per_page_option
      end
      
      @issue_count = @query.issue_count
      @issue_pages = Paginator.new self, @issue_count, limit, params['page']
      @issues = @query.issues(:include => [:assigned_to, :tracker, :priority, :category, :fixed_version],
                              :order => sort_clause, 
                              :offset => @issue_pages.current.offset, 
                              :limit => limit)
      @issue_count_by_group = @query.issue_count_by_group
      
      respond_to do |format|
        format.html { render :template => 'issues/index.rhtml', :layout => !request.xhr? }
        format.xml  { render :layout => false }
        format.json { render :text => @issues.to_json, :layout => false }
        format.atom { render_feed(@issues, :title => "#{@project || Setting.app_title}: #{l(:label_issue_plural)}") }
        format.csv  { send_data(issues_to_csv(@issues, @project), :type => 'text/csv; header=present', :filename => 'export.csv') }
        format.pdf  { send_data(issues_to_pdf(@issues, @project, @query), :type => 'application/pdf', :filename => 'export.pdf') }
      end
    else
      # Send html if the query is not valid
      render(:template => 'issues/index.rhtml', :layout => !request.xhr?)
    end
  rescue ActiveRecord::RecordNotFound
    render_404
  end
  
  def show
    @journals = @issue.journals.find(:all, :include => [:user, :details], :order => "#{Journal.table_name}.created_on ASC")
    @journals.each_with_index {|j,i| j.indice = i+1}
    @journals.reverse! if User.current.wants_comments_in_reverse_order?
    @changesets = @issue.changesets.visible.all
    @changesets.reverse! if User.current.wants_comments_in_reverse_order?
    @allowed_statuses = @issue.new_statuses_allowed_to(User.current)
    @edit_allowed = User.current.allowed_to?(:edit_issues, @project)
    @priorities = IssuePriority.all
    @time_entry = TimeEntry.new
    respond_to do |format|
      format.html { render :template => 'issues/show.rhtml' }
      format.xml  { render :layout => false }
      format.json { render :text => @issue.to_json, :layout => false }
      format.atom { render :template => 'journals/index', :layout => false, :content_type => 'application/atom+xml' }
      format.pdf  { send_data(issue_to_pdf(@issue), :type => 'application/pdf', :filename => "#{@project.identifier}-#{@issue.id}.pdf") }
    end
  end

  # Add a new issue
  # The new issue will be created from an existing one if copy_from parameter is given
  def new
    respond_to do |format|
      format.html { render :action => 'new', :layout => !request.xhr? }
      format.js { render :partial => 'attributes' }
    end
  end

  def create
    call_hook(:controller_issues_new_before_save, { :params => params, :issue => @issue })
    if @issue.save
      attachments = Attachment.attach_files(@issue, params[:attachments])
      render_attachment_warning_if_needed(@issue)
      flash[:notice] = l(:notice_successful_create)
      call_hook(:controller_issues_new_after_save, { :params => params, :issue => @issue})
      respond_to do |format|
        format.html {
          redirect_to(params[:continue] ? { :action => 'new', :issue => {:tracker_id => @issue.tracker, :parent_issue_id => @issue.parent_issue_id}.reject {|k,v| v.nil?} } :
                      { :action => 'show', :id => @issue })
        }
        format.xml  { render :action => 'show', :status => :created, :location => url_for(:controller => 'issues', :action => 'show', :id => @issue) }
        format.json { render :text => @issue.to_json, :status => :created, :location => url_for(:controller => 'issues', :action => 'show'), :layout => false }
      end
      return
    else
      respond_to do |format|
        format.html { render :action => 'new' }
        format.xml  { render(:xml => @issue.errors, :status => :unprocessable_entity); return }
        format.json { render :text => object_errors_to_json(@issue), :status => :unprocessable_entity, :layout => false }
      end
    end
  end
  
  # Attributes that can be updated on workflow transition (without :edit permission)
  # TODO: make it configurable (at least per role)
  UPDATABLE_ATTRS_ON_TRANSITION = %w(status_id assigned_to_id fixed_version_id done_ratio) unless const_defined?(:UPDATABLE_ATTRS_ON_TRANSITION)
  
  def edit
    update_issue_from_params

    @journal = @issue.current_journal

    respond_to do |format|
      format.html { }
      format.xml  { }
    end
  end

  def update
    update_issue_from_params

    if @issue.save_issue_with_child_records(params, @time_entry)
      render_attachment_warning_if_needed(@issue)
      flash[:notice] = l(:notice_successful_update) unless @issue.current_journal.new_record?

      respond_to do |format|
        format.html { redirect_back_or_default({:action => 'show', :id => @issue}) }
        format.xml  { head :ok }
        format.json  { head :ok }
      end
    else
      render_attachment_warning_if_needed(@issue)
      flash[:notice] = l(:notice_successful_update) unless @issue.current_journal.new_record?
      @journal = @issue.current_journal

      respond_to do |format|
        format.html { render :action => 'edit' }
        format.xml  { render :xml => @issue.errors, :status => :unprocessable_entity }
        format.json { render :text => object_errors_to_json(@issue), :status => :unprocessable_entity, :layout => false }
      end
    end
  end

  # Bulk edit a set of issues
  def bulk_edit
    @issues.sort!
    @available_statuses = Workflow.available_statuses(@project)
    @custom_fields = @project.all_issue_custom_fields
  end

  def bulk_update
    @issues.sort!
    attributes = parse_params_for_bulk_issue_attributes(params)

    unsaved_issue_ids = []
    @issues.each do |issue|
      issue.reload
      journal = issue.init_journal(User.current, params[:notes])
      issue.safe_attributes = attributes
      call_hook(:controller_issues_bulk_edit_before_save, { :params => params, :issue => issue })
      unless issue.save
        # Keep unsaved issue ids to display them in flash error
        unsaved_issue_ids << issue.id
      end
    end
    set_flash_from_bulk_issue_save(@issues, unsaved_issue_ids)
    redirect_back_or_default({:controller => 'issues', :action => 'index', :project_id => @project})
  end
  
  def destroy
    @hours = TimeEntry.sum(:hours, :conditions => ['issue_id IN (?)', @issues]).to_f
    if @hours > 0
      case params[:todo]
      when 'destroy'
        # nothing to do
      when 'nullify'
        TimeEntry.update_all('issue_id = NULL', ['issue_id IN (?)', @issues])
      when 'reassign'
        reassign_to = @project.issues.find_by_id(params[:reassign_to_id])
        if reassign_to.nil?
          flash.now[:error] = l(:error_issue_not_found_in_project)
          return
        else
          TimeEntry.update_all("issue_id = #{reassign_to.id}", ['issue_id IN (?)', @issues])
        end
      else
        unless params[:format] == 'xml' || params[:format] == 'json'
          # display the destroy form if it's a user request
          return
        end
      end
    end
    @issues.each(&:destroy)
    respond_to do |format|
      format.html { redirect_to :action => 'index', :project_id => @project }
      format.xml  { head :ok }
      format.json  { head :ok }
    end
  end

private
  def find_issue
    @issue = Issue.find(params[:id], :include => [:project, :tracker, :status, :author, :priority, :category])
    @project = @issue.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end
  
  def find_project
    project_id = (params[:issue] && params[:issue][:project_id]) || params[:project_id]
    @project = Project.find(project_id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end
  
  # Used by #edit and #update to set some common instance variables
  # from the params
  # TODO: Refactor, not everything in here is needed by #edit
  def update_issue_from_params
    @allowed_statuses = @issue.new_statuses_allowed_to(User.current)
    @priorities = IssuePriority.all
    @edit_allowed = User.current.allowed_to?(:edit_issues, @project)
    @time_entry = TimeEntry.new
    
    @notes = params[:notes] || (params[:issue].present? ? params[:issue][:notes] : nil)
    @issue.init_journal(User.current, @notes)
    # User can change issue attributes only if he has :edit permission or if a workflow transition is allowed
    if (@edit_allowed || !@allowed_statuses.empty?) && params[:issue]
      attrs = params[:issue].dup
      attrs.delete_if {|k,v| !UPDATABLE_ATTRS_ON_TRANSITION.include?(k) } unless @edit_allowed
      attrs.delete(:status_id) unless @allowed_statuses.detect {|s| s.id.to_s == attrs[:status_id].to_s}
      @issue.safe_attributes = attrs
    end

  end

  # TODO: Refactor, lots of extra code in here
  def build_new_issue_from_params
    if params[:id].blank?
      @issue = Issue.new
      @issue.copy_from(params[:copy_from]) if params[:copy_from]
      @issue.project = @project
    else
      @issue = @project.issues.visible.find(params[:id])
    end
    
    @issue.project = @project
    # Tracker must be set before custom field values
    @issue.tracker ||= @project.trackers.find((params[:issue] && params[:issue][:tracker_id]) || params[:tracker_id] || :first)
    if @issue.tracker.nil?
      render_error l(:error_no_tracker_in_project)
      return false
    end
    if params[:issue].is_a?(Hash)
      @issue.safe_attributes = params[:issue]
      @issue.watcher_user_ids = params[:issue]['watcher_user_ids'] if User.current.allowed_to?(:add_issue_watchers, @project)
    end
    @issue.author = User.current
    @issue.start_date ||= Date.today
    @priorities = IssuePriority.all
    @allowed_statuses = @issue.new_statuses_allowed_to(User.current, true)
  end

  def check_for_default_issue_status
    if IssueStatus.default.nil?
      render_error l(:error_no_default_issue_status)
      return false
    end
  end

  def parse_params_for_bulk_issue_attributes(params)
    attributes = (params[:issue] || {}).reject {|k,v| v.blank?}
    attributes.keys.each {|k| attributes[k] = '' if attributes[k] == 'none'}
    attributes[:custom_field_values].reject! {|k,v| v.blank?} if attributes[:custom_field_values]
    attributes
  end
end
