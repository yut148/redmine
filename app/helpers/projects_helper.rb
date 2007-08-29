# redMine - project management software
# Copyright (C) 2006  Jean-Philippe Lang
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

module ProjectsHelper
  def link_to_version(version, options = {})
    return '' unless version && version.is_a?(Version)
    link_to version.name, {:controller => 'projects',
                           :action => 'roadmap',
                           :id => version.project_id,
                           :completed => (version.completed? ? 1 : nil),
                           :anchor => version.name
                          }, options
  end
  
  def new_issue_selector
    trackers = Tracker.find(:all, :order => 'position')
    form_tag({:controller => 'projects', :action => 'add_issue', :id => @project}, :method => :get) +
      select_tag('tracker_id', '<option></option' + options_from_collection_for_select(trackers, 'id', 'name'),
        :onchange => "if (this.value != '') {this.form.submit()}") +
      end_form_tag
  end
end
