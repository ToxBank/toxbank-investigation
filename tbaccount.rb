module OpenTox

  # define RDF vocabularies
  # use 'RDF' as 'http://www.w3.org/1999/02/22-rdf-syntax-ns#' prefix
  RDF::TB   = RDF::Vocabulary.new "http://onto.toxbank.net/api/"
  RDF::TBU  = RDF::Vocabulary.new "#{$user_service[:uri]}/user/"
  RDF::TBO  = RDF::Vocabulary.new "#{$user_service[:uri]}/organisation/"
  RDF::TBPT = RDF::Vocabulary.new "#{$user_service[:uri]}/project/"
  RDF::OWL = RDF::Vocabulary.new "http://www.w3.org/2002/07/owl#"
  RDF::ISA = RDF::Vocabulary.new "http://onto.toxbank.net/isa/"

  CLASSES << "TBAccount"

  # Get rdf representation for a user, organisation or project from the ToxBank service 
  # @see http://api.toxbank.net/index.php/User ToxBank API User
  # @see http://api.toxbank.net/index.php/Organisation ToxBank API Organisation
  # @see http://api.toxbank.net/index.php/Project ToxBank API Project
  # @see http://api.toxbank.net/index.php/Protocol#Security ToxBank API Security
  # @example TBAccount
  #   require "opentox-server"
  #   User1 = OpenTox::TBAccount.new("http://uri_to_toxbankservice/toxbank/user/U123", subjectid)
  #   puts User1.ldap_dn #=> "uid=username,ou=people,dc=opentox,dc=org"
  #   User1.send_policy("http://uri_toprotect/bla/foo") #=> creates new read policy for http://uri_toprotect/bla/foo
  class TBAccount
    include OpenTox

    # Get hasAccount value of a user,organisation or project from ToxBank service
    # @return [String] username
    def account
      @account ||= get_account
    end

    # Generates LDAP Distinguished Name (DN)
    # @return [String] LDAP Distinguished Name (DN)
    def ldap_dn
      @uri.match(RDF::TBU.to_s) ? "uid=#{self.account},ou=people,dc=opentox,dc=org" : "cn=#{self.account},ou=groups,dc=opentox,dc=org"
    end

    # Get LDAP type - returns 'LDAPUsers' if the TBAccount.uri is a user URI   
    # @return [String] 'LDAPUsers' or 'LDAPGroups'
    def ldap_type
      @uri.match(RDF::TBU.to_s) ? "LDAPUsers" : "LDAPGroups"
    end

    # GET policy XML 
    # @param [String,String] URI,Type URI to protect, Access-rights < "all", "readwrite", "read" (default) >
    # @return [String] policy in XML 
    def get_policy uri, type="read"
      policy(uri, type)
    end

    # sends policy to opensso server
    # @param (see #get_policy) 
    def send_policy uri, type="read"
      OpenTox::Authorization.create_policy(policy(uri, type), @subjectid)
    end

    # Change account URI into RDF prefixed Version e.G.: "http://toxbanktest1.opentox.org:8080/toxbank/user/U2" becomes "TBU:U2"
    # @example 
    #   user = OpenTox::TBAccount.new("http://uri_to_toxbankservice/toxbank/user/U2", subjectid)
    #   puts user.ns_uri #=> "RDF::TBU:U2"
    # @return [String] prefixed URI of a user/organisation/project
    def ns_uri
      out = "TBU:#{@uri.split('/')[-1]}"  if @uri.match(RDF::TBU.to_s)
      out = "TBO:#{@uri.split('/')[-1]}"  if @uri.match(RDF::TBO.to_s)
      out = "TBPT:#{@uri.split('/')[-1]}" if @uri.match(RDF::TBPT.to_s)
      out
    end

    private

    # Get rdf from user service and returns username
    # @private 
    def get_account
      get "application/rdf+xml" # get rdfxml instead of ntriples
      # do not catch errors as this will lead do follow up problems
      # error handling is implemented at a lower level in opentox-client
      self[RDF::TB.hasAccount]
    end

    def get mime_type="application/rdf+xml"
       response = `curl -Lk -X GET -H "Accept:#{mime_type}" -H "subjectid:#{@subjectid}" #{@uri}`.chomp
       parse_rdfxml response if mime_type == "application/rdf+xml"
    end

    # creates policy
    def policy uri, type="read"
      return <<-EOS
<!DOCTYPE Policies PUBLIC "-//Sun Java System Access Manager7.1 2006Q3 Admin CLI DTD//EN" "jar://com/sun/identity/policy/policyAdmin.dtd">
<Policies>
  <Policy name="tbi-#{self.account}-#{self.ldap_type[4,6].downcase}-#{Time.now.strftime("%Y-%m-%d-%H-%M-%S-x") + rand(1000).to_s}" referralPolicy="false" active="true">
    <Rule name="rule_name">
      <ServiceName name="iPlanetAMWebAgentService" />
      <ResourceName name="#{uri}"/>
      #{get_permissions(type)}
    </Rule>
    <Subjects name="subjects_name" description="">
      <Subject name="#{self.account}" type="#{self.ldap_type}" includeType="inclusive">
        <AttributeValuePair>
          <Attribute name="Values"/>
          <Value>#{self.ldap_dn}</Value>
        </AttributeValuePair>
      </Subject>
    </Subjects>
  </Policy>
</Policies>
      EOS
    end

    # creates permission part of policy
    def get_permissions type
      requests = case type
      when "all"
        ["GET", "POST", "PUT", "DELETE"]
      when "readwrite"
        ["GET", "POST", "PUT"]
      else
        ["GET"]
      end
      out=""
      requests.each{|r| out = "#{out}<AttributeValuePair><Attribute name=\"#{r}\" /><Value>allow</Value></AttributeValuePair>\n"}
      return out
    end

  end

  # ToxBank-investigation specific extension to OpenTox::Authorization in opentox-client
  # @see http://rubydoc.info/gems/opentox-client/frames opentox-client documentation
  module Authorization

    # Create policy for PI-user (owner of subjectid)
    # @param [String, String] URI,subjectid URI to create a policy for, subjectid
    def self.create_pi_policy uri, subjectid
      user = get_user(subjectid)
      #piuri = RestClientWrapper.get("#{RDF::TBU.to_s}?username=#{user}", nil, {:Accept => "text/uri-list", :subjectid => subjectid}).sub("\n","")
      piuri =`curl -Lk -X GET -H "Accept:text/uri-list" -H "subjectid:#{subjectid}" #{RDF::TBU.to_s}?username=#{user}`.chomp.sub("\n","")
      piaccount = TBAccount.new(piuri, subjectid)
      piaccount.send_policy(uri, "all")
    end

    # Delete all policies for Users or Groups of an investigation except the policy of the subjectid-owner.
    # @param [String, String, String] URI,LDAPtype,subjectid URI to protect, LDAPUsers or LDAPGroups, subjectid
    def self.reset_policies uri, type, subjectid
      policies = self.list_uri_policies(uri, subjectid)
      user = get_user(subjectid)
      policies.keep_if{|policy| policy =~ /^tbi-\w+-#{type}-*/ }
      policies.delete_if{|policy| policy =~ /^tbi-#{user}-users-*/ }
      policies.each{|policy| self.delete_policy(policy, subjectid) }
    end

  end
end
