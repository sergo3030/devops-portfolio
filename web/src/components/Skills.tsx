import { useId, useState } from 'react';
import type { SkillGroup } from '../generated/content';
import { countSkills, filterSkills } from '../lib/skills';
import { Section } from './Section';
import styles from './Skills.module.css';

type Props = { groups: SkillGroup[] };

export function Skills({ groups }: Props) {
  const [query, setQuery] = useState('');
  const inputId = useId();
  if (groups.length === 0) return null;

  const visible = filterSkills(groups, query);
  const count = countSkills(visible);
  return (
    <Section heading="Skills">
      <div className={styles.filter}>
        <label htmlFor={inputId} className={styles.filterLabel}>
          Filter skills
        </label>
        <input
          id={inputId}
          className={styles.filterInput}
          type="search"
          value={query}
          onChange={(event) => {
            setQuery(event.target.value);
          }}
          autoComplete="off"
          spellCheck={false}
        />
      </div>
      <p role="status" className={styles.count}>
        {count === 0 ? 'No skills match.' : `${count} ${count === 1 ? 'skill' : 'skills'} shown`}
      </p>
      {visible.map((group) => {
        const total = groups.find((original) => original.category === group.category)?.items.length;
        const hidden = Math.max(0, (total ?? group.items.length) - group.items.length);
        return (
          <div key={group.category} className={styles.group}>
            <h3 className={styles.category}>{group.category}</h3>
            <ul className={styles.items}>
              {group.items.map((item) => (
                <li key={item} className={styles.item}>
                  {item}
                </li>
              ))}
              {Array.from({ length: hidden }, (_, slot) => (
                <li key={`ghost-${String(slot)}`} className={styles.ghost} aria-hidden="true" />
              ))}
            </ul>
          </div>
        );
      })}
    </Section>
  );
}
