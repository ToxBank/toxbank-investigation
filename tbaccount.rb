module OpenTox

  # define RDF vocabularies
  RDF::TB   = RDF::Vocabulary.new "http://onto.toxbank.net/api/"
  RDF::TBU  = RDF::Vocabulary.new "http://toxbanktest1.opentox.org:8080/toxbank/user/"
  RDF::TBO  = RDF::Vocabulary.new "http://toxbanktest1.opentox.org:8080/toxbank/organisation/"
  RDF::TBPT = RDF::Vocabulary.new "http://toxbanktest1.opentox.org:8080/toxbank/project/"

  CLASSES << "TBAccount"

  # add new OpenTox class
  c = Class.new do
    include OpenTox
    extend OpenTox::ClassMethods
  end
  OpenTox.const_set "TBAccount",c

  #Get rdf reppresentation for a user,organisation or project from the ToxBank service
  #@example TBAccount
  #  require "opentox-server"
  #  User1 = OpenTox::TBAccount.new("http://uri_to_toxbankservice/toxbank/user/U123", subjectid)
  #  puts User1.ldap_dn #=> "uid=username,ou=people,dc=opentox,dc=org"
  #  User1.send_policy("http://uri_toprotect/bla/foo") #=> creates new read policy for http://uri_toprotect/bla/foo
  class TBAccount

    # Get hasAccount value of a user,organisation or project from ToxBank service
    def account
      @account ||= get_account
    end

    # returns LDAP Distinguished Name (DN)
    def ldap_dn
      @uri.match(RDF::TBU.to_s) ? "uid=#{self.account},ou=people,dc=opentox,dc=org" : "cn=#{self.account},ou=groups,dc=opentox,dc=org"
    end

    # returns LDAP type
    def ldap_type
      @uri.match(RDF::TBU.to_s) ? "LDAPUsers" : "LDAPGroups"
    end

    def get_policy uri, type="read"
      policy(uri, type)
    end

    # sends policy to opensso server
    def send_policy uri, type="read"
      OpenTox::Authorization.create_policy(policy(uri, type), @subjectid)
    end

    # Get prefixed account URI e.G.: TBU:U2
    def ns_uri
      out = "TBU:#{@uri.split('/')[-1]}"  if @uri.match(RDF::TBU.to_s)
      out = "TBO:#{@uri.split('/')[-1]}"  if @uri.match(RDF::TBO.to_s)
      out = "TBPT:#{@uri.split('/')[-1]}" if @uri.match(RDF::TBPT.to_s)
      out
    end

    private

    # Get rdf from user service and returns username
    def get_account
      begin
        self.metadata[RDF::TB.hasAccount][0].value
      rescue
        $logger.error "OpenTox::TBAccount get_account can not get username."
        return nil
      end
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
      <Subject name="subject_name" type="#{self.ldap_type}" includeType="inclusive">
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

  module Authorization

    # Create policy for PI-user (owner of subjectid)
    # @param [String, String] URI,subjectid URI to create a policy for
    def self.create_pi_policy uri, subjectid
      user = get_user(subjectid)
      piuri = RestClientWrapper.get("http://toxbanktest1.opentox.org:8080/toxbank/user?username=#{user}", nil, {:Accept => "text/uri-list", :subjectid => subjectid}).sub("\n","")
      piaccount = TBAccount.new(piuri, subjectid)
      piaccount.send_policy(uri, "all")
    end

    # URI is published? Has more than the PI policy?
    # @param [String, String] URI,subjectid
    def self.published? uri, subjectid
      return list_uri_policies(uri, subjectid).size > 1
    end

  end
end