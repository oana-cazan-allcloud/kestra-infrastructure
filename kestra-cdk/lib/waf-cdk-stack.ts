import {
  Stack,
  StackProps,
  aws_elasticloadbalancingv2 as elbv2,
  aws_wafv2 as wafv2,
  aws_logs as logs,
  aws_iam as iam,
  Duration,
  CfnOutput,
} from 'aws-cdk-lib';
import { Construct } from 'constructs';

export interface WafStackProps extends StackProps {
  alb: elbv2.IApplicationLoadBalancer;
  /** Path to protect with rate limiting (e.g., "/webhook/jira") */
  webhookPath?: string;
  /** Requests per 5 minutes per IP (e.g., 300) */
  rateLimitPer5Min?: number;
  /** Optional Geo allowlist (ISO 2-letter codes, e.g., ["DE","RO","FR"]) */
  allowCountries?: string[];
  /** Optional IP allowlist CIDRs (e.g., ["198.51.100.0/24"]) */
  ipAllowList?: string[];
  /** Optional IP blocklist CIDRs */
  ipBlockList?: string[];
}

export class WafStack extends Stack {
  constructor(scope: Construct, id: string, props: WafStackProps) {
    super(scope, id, props);

    const {
      alb,
      webhookPath = '/webhook',
      rateLimitPer5Min = 300, // per 5 minutes per IP
      allowCountries,
      ipAllowList,
      ipBlockList,
    } = props;

    // ---------- Optional IP sets ----------
    let allowIpSet: wafv2.CfnIPSet | undefined;
    if (ipAllowList && ipAllowList.length) {
      allowIpSet = new wafv2.CfnIPSet(this, 'WafAllowIpSet', {
        addresses: ipAllowList,
        ipAddressVersion: 'IPV4',
        scope: 'REGIONAL',
        name: 'kestra-allow-ips',
        description: 'IPs allowed to bypass other rules',
      });
    }

    let blockIpSet: wafv2.CfnIPSet | undefined;
    if (ipBlockList && ipBlockList.length) {
      blockIpSet = new wafv2.CfnIPSet(this, 'WafBlockIpSet', {
        addresses: ipBlockList,
        ipAddressVersion: 'IPV4',
        scope: 'REGIONAL',
        name: 'kestra-block-ips',
        description: 'IPs explicitly blocked',
      });
    }

    // ---------- Build rules array in priority order ----------
    const rules: wafv2.CfnWebACL.RuleProperty[] = [];

    // 1) Allowlist (bypass): allow early if in allow list
    if (allowIpSet) {
      rules.push({
        name: 'AllowListedIPs',
        priority: 0,
        action: { allow: {} },
        statement: {
          ipSetReferenceStatement: { arn: allowIpSet.attrArn },
        },
        visibilityConfig: {
          metricName: 'AllowListedIPs',
          cloudWatchMetricsEnabled: true,
          sampledRequestsEnabled: true,
        },
      });
    }

    // 2) Blocklist: block early if in block list
    if (blockIpSet) {
      rules.push({
        name: 'BlockedIPs',
        priority: 1,
        action: { block: {} },
        statement: {
          ipSetReferenceStatement: { arn: blockIpSet.attrArn },
        },
        visibilityConfig: {
          metricName: 'BlockedIPs',
          cloudWatchMetricsEnabled: true,
          sampledRequestsEnabled: true,
        },
      });
    }

    // 3) Rate limit for webhook path
    rules.push({
      name: 'RateLimitWebhook',
      priority: 2,
      action: { block: {} },
      statement: {
        rateBasedStatement: {
          limit: rateLimitPer5Min, // requests per 5 min per IP
          aggregateKeyType: 'IP',
          scopeDownStatement: {
            byteMatchStatement: {
              fieldToMatch: { uriPath: {} },
              positionalConstraint: 'STARTS_WITH',
              searchString: webhookPath,
              textTransformations: [{ priority: 0, type: 'NONE' }],
            },
          },
        },
      },
      visibilityConfig: {
        metricName: 'RateLimitWebhook',
        cloudWatchMetricsEnabled: true,
        sampledRequestsEnabled: true,
      },
    });

    // 4) Geo rule (block if NOT in the allowed list)
    if (allowCountries && allowCountries.length) {
      rules.push({
        name: 'GeoAllowOnly',
        priority: 3,
        action: { block: {} },
        statement: {
          notStatement: {
            statement: {
              geoMatchStatement: {
                countryCodes: allowCountries,
              },
            },
          },
        },
        visibilityConfig: {
          metricName: 'GeoAllowOnly',
          cloudWatchMetricsEnabled: true,
          sampledRequestsEnabled: true,
        },
      });
    }

    // 5) AWS Managed Rule Groups
    const managedGroups: Array<{ name: string; vendor: string; priority: number }> = [
      { name: 'AWSManagedRulesCommonRuleSet', vendor: 'AWS', priority: 10 },
      { name: 'AWSManagedRulesKnownBadInputsRuleSet', vendor: 'AWS', priority: 11 },
      { name: 'AWSManagedRulesAmazonIpReputationList', vendor: 'AWS', priority: 12 },
      { name: 'AWSManagedRulesAnonymousIpList', vendor: 'AWS', priority: 13 },
      { name: 'AWSManagedRulesSQLiRuleSet', vendor: 'AWS', priority: 14 },
      // (Optional, paid) { name: 'AWSManagedRulesBotControlRuleSet', vendor: 'AWS', priority: 15 },
    ];

    for (const g of managedGroups) {
      rules.push({
        name: g.name,
        priority: g.priority,
        overrideAction: { none: {} },
        statement: {
          managedRuleGroupStatement: {
            name: g.name,
            vendorName: g.vendor,
          },
        },
        visibilityConfig: {
          metricName: g.name,
          cloudWatchMetricsEnabled: true,
          sampledRequestsEnabled: true,
        },
      });
    }

    // ---------- Web ACL ----------
    const webAcl = new wafv2.CfnWebACL(this, 'KestraWebAcl', {
      name: 'kestra-alb-web-acl',
      scope: 'REGIONAL',
      defaultAction: { allow: {} },
      visibilityConfig: {
        metricName: 'kestraWebAcl',
        cloudWatchMetricsEnabled: true,
        sampledRequestsEnabled: true,
      },
      rules,
    });

    // ---------- Associate to ALB ----------
    new wafv2.CfnWebACLAssociation(this, 'KestraWebAclAssociation', {
      resourceArn: alb.loadBalancerArn,
      webAclArn: webAcl.attrArn,
    });

    // ---------- WAF Logging to CloudWatch Logs ----------
    const logGroup = new logs.LogGroup(this, 'WafLogGroup', {
      logGroupName: '/aws/waf/kestra',
      retention: logs.RetentionDays.ONE_MONTH,
    });

    // Allow WAF to write to this log group
    logGroup.addToResourcePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('waf.amazonaws.com')],
        actions: [
          'logs:CreateLogStream',
          'logs:PutLogEvents',
          'logs:PutLogEventsBatch',
          'logs:CreateLogGroup',
          'logs:DescribeLogStreams',
        ],
        resources: [logGroup.logGroupArn, `${logGroup.logGroupArn}:*`],
        // Scope to this account; SourceArn condition is optional here to avoid circular dependency
        conditions: {
          StringEquals: { 'aws:SourceAccount': this.account },
        },
      })
    );

    new wafv2.CfnLoggingConfiguration(this, 'WafLogging', {
      resourceArn: webAcl.attrArn,
      logDestinationConfigs: [logGroup.logGroupArn],
    });

    // ---------- Outputs ----------
    new CfnOutput(this, 'WebAclArn', { value: webAcl.attrArn });
    new CfnOutput(this, 'WafLogGroupName', { value: logGroup.logGroupName });
  }
}
